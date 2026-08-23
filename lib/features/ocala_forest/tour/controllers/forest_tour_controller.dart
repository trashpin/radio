import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_audio_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_boundary.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_story_type.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_subject.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_type.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/services/forest_tour_engine.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/services/forest_tour_narration_service.dart';

enum TourStatus { idle, active, ended }

/// GPS accuracy worse than this is treated as "weak signal" (spec §19) —
/// the tour still runs, but tells the visitor and treats any "exact
/// geofence" match more skeptically rather than pretending it's precise.
const double kPoorGpsAccuracyMeters = 100;

class ForestTourState {
  const ForestTourState({
    this.status = TourStatus.idle,
    this.tourType = TourType.general,
    this.currentSubjectName,
    this.currentText,
    this.currentStoryType = TourStoryType.general,
    this.loading = false,
    this.statusMessage,
    this.gpsWarning,
    this.error,
    this.segmentsPlayed = 0,
  });

  final TourStatus status;
  final TourType tourType;
  final String? currentSubjectName;
  final String? currentText;
  final TourStoryType currentStoryType;
  final bool loading;

  /// Brief, transient "Finding your location…" / "Finding stories near
  /// you…" status shown only while starting (spec §9).
  final String? statusMessage;

  /// Set once GPS accuracy is known to be poor (spec §19) — stays visible
  /// for the rest of the tour as a standing disclosure, not just a toast.
  final String? gpsWarning;
  final String? error;
  final int segmentsPlayed;

  bool get isActive => status == TourStatus.active;

  ForestTourState copyWith({
    TourStatus? status,
    TourType? tourType,
    String? currentSubjectName,
    String? currentText,
    TourStoryType? currentStoryType,
    bool? loading,
    String? statusMessage,
    bool clearStatusMessage = false,
    String? gpsWarning,
    String? error,
    bool clearError = false,
    int? segmentsPlayed,
  }) =>
      ForestTourState(
        status: status ?? this.status,
        tourType: tourType ?? this.tourType,
        currentSubjectName: currentSubjectName ?? this.currentSubjectName,
        currentText: currentText ?? this.currentText,
        currentStoryType: currentStoryType ?? this.currentStoryType,
        loading: loading ?? this.loading,
        statusMessage: clearStatusMessage ? null : (statusMessage ?? this.statusMessage),
        gpsWarning: gpsWarning ?? this.gpsWarning,
        error: clearError ? null : (error ?? this.error),
        segmentsPlayed: segmentsPlayed ?? this.segmentsPlayed,
      );
}

/// "Take Me On A Tour" — a GPS/geofence-DRIVEN tour, not a generic one
/// (per the refinement spec's own emphasis). Orchestrates EXISTING
/// infrastructure only: GPS (`gpsControllerProvider`), the existing forest
/// locations/trails data, [ForestTourEngine] (which itself wraps the same
/// `LocationTriggerEngine`/`nearestTrailId` every other forest feature
/// already uses — no new geofence/location system), the `forest-tour` Edge
/// Function (OpenAI + ElevenLabs, the SAME integrations copilot-line/
/// forest-discovery/forest-trail-audio already use), and
/// [ForestAudioController] (the SAME dedicated forest audio player, so
/// this tour's audio can never fight the radio).
///
/// "Tour history" is a plain in-memory `Set`/`List` scoped to one tour —
/// the simplest approach that fits an app with no real per-user account
/// system to hang persistent history off of.
class ForestTourController extends Notifier<ForestTourState> {
  final _engine = ForestTourEngine();
  final Set<String> _discussedIds = {};
  final List<String> _discussedNames = [];
  bool _wired = false;
  List<ForestLocation> _locations = const [];
  List<ForestTrail> _trails = const [];
  ForestBoundary? _forest;

  @override
  ForestTourState build() => const ForestTourState();

  Future<void> startTour({
    TourType tourType = TourType.general,
    ForestLocation? anchorLocation, // future QR compat — start already-focused on one location
  }) async {
    _discussedIds.clear();
    _discussedNames.clear();
    _locations = ref.read(forestLocationsProvider).value ?? const [];
    _trails = ref.read(forestTrailsProvider).value ?? const [];
    _forest = ref.read(ocalaForestBoundaryProvider).value;

    state = ForestTourState(
      status: TourStatus.active,
      tourType: tourType,
      loading: true,
      statusMessage: 'Finding your location…',
    );

    if (!_wired) {
      _wired = true;
      ref.listen<TravelContext>(gpsControllerProvider, (_, ctx) {
        if (!state.isActive) return;
        _handleMovement(ctx);
      });
    }

    // spec §1: never invent/estimate the visitor's location — wait for a
    // real fix from the EXISTING GPS system rather than guessing.
    final fix = await _waitForGpsFix();
    if (!state.isActive) return; // ended while awaiting
    if (fix == null) {
      state = ForestTourState(
        status: TourStatus.idle,
        error: "Couldn't get your location — move to an open area and try again.",
      );
      return;
    }

    final gpsWarning = (fix.accuracyMeters == null || fix.accuracyMeters! > kPoorGpsAccuracyMeters)
        ? 'Your GPS signal is weak. Move to an open area for a more accurate tour.'
        : null;
    state = state.copyWith(statusMessage: 'Finding stories near you…', gpsWarning: gpsWarning);

    final narration = ref.read(forestTourNarrationServiceProvider);
    final intro = await narration.requestIntro(forest: _forest);
    if (!state.isActive) return;
    if (intro == null) {
      state = state.copyWith(
        loading: false,
        clearStatusMessage: true,
        error: "Couldn't start the tour — check your connection and try again.",
      );
      return;
    }
    state = state.copyWith(
      currentSubjectName: _forest?.name ?? 'Ocala National Forest',
      currentText: intro.text,
      currentStoryType: TourStoryType.general,
      segmentsPlayed: 1,
    );
    await _playAudio(title: '🎧 Tour Introduction', audioUrl: intro.audioUrl, text: intro.text);

    // spec §4/§10: the FIRST real segment must always say something
    // geographically relevant — never silence, even with nothing specific
    // nearby — so this uses the never-null on-demand path, not the
    // passive movement path (which is allowed to stay quiet).
    final subject = anchorLocation != null
        ? TourSubject.forLocation(anchorLocation)
        : _engine.onDemand(
            lat: fix.latitude,
            lng: fix.longitude,
            locations: _locations,
            trails: _trails,
            recentlyDiscussedIds: _discussedIds,
            tourType: tourType,
          );
    await _playSubject(subject, lat: fix.latitude, lng: fix.longitude, accuracyMeters: fix.accuracyMeters);
  }

  Future<GPSLocation?> _waitForGpsFix({Duration timeout = const Duration(seconds: 15)}) async {
    final existing = ref.read(gpsControllerProvider).location;
    if (existing != null) return existing;

    final completer = Completer<GPSLocation?>();
    late final ProviderSubscription sub;
    sub = ref.listen<TravelContext>(gpsControllerProvider, (_, ctx) {
      final loc = ctx.location;
      if (loc != null && !completer.isCompleted) {
        completer.complete(loc);
      }
    });
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      sub.close();
    }
  }

  void _handleMovement(TravelContext ctx) {
    final fix = ctx.location;
    if (fix == null) return;
    final subject = _engine.onLocation(
      fix: fix,
      locations: _locations,
      trails: _trails,
      recentlyDiscussedIds: _discussedIds,
      tourType: state.tourType,
    );
    if (subject == null) return; // spec §11: stay quiet, this is normal
    _playSubject(subject, lat: fix.latitude, lng: fix.longitude, accuracyMeters: fix.accuracyMeters);
  }

  /// "🎙️ Tell Me Something" and "⏭️ Next Story" — both an explicit,
  /// on-demand request that uses the visitor's CURRENT GPS location right
  /// now (spec §13: never a random pick from across the whole forest),
  /// bypassing the movement cooldown but still respecting the anti-repeat
  /// history.
  Future<void> tellMeSomething() async {
    if (!state.isActive) return;
    final fix = ref.read(gpsControllerProvider).location;
    if (fix == null) {
      state = state.copyWith(error: 'Waiting for a GPS fix — try again in a moment.');
      return;
    }
    final subject = _engine.onDemand(
      lat: fix.latitude,
      lng: fix.longitude,
      locations: _locations,
      trails: _trails,
      recentlyDiscussedIds: _discussedIds,
      tourType: state.tourType,
    );
    await _playSubject(subject, lat: fix.latitude, lng: fix.longitude, accuracyMeters: fix.accuracyMeters);
  }

  Future<void> nextStory() => tellMeSomething();

  Future<void> _playSubject(
    TourSubject subject, {
    required double lat,
    required double lng,
    double? accuracyMeters,
  }) async {
    state = state.copyWith(loading: true, clearError: true, clearStatusMessage: true);
    final narration = ref.read(forestTourNarrationServiceProvider);
    final result = await narration.requestForSubject(
      subject,
      forest: _forest,
      recentlyMentioned: List.unmodifiable(_discussedNames),
      nearbySummary: _nearbySummaryExcluding(subject.id, lat, lng),
      gpsAccuracyMeters: accuracyMeters,
    );
    if (!state.isActive) return;
    if (result == null) {
      state = state.copyWith(loading: false, error: "Couldn't generate that segment — try again.");
      return;
    }
    _discussedIds.add(subject.id);
    _discussedNames.add(subject.name);
    final storyType = TourStoryType.values
        .firstWhere((t) => t.id == result.storyType, orElse: () => TourStoryType.general);
    state = state.copyWith(
      loading: false,
      currentSubjectName: subject.name,
      currentText: result.text,
      currentStoryType: storyType,
      segmentsPlayed: state.segmentsPlayed + 1,
    );
    await _playAudio(title: subject.name, audioUrl: result.audioUrl, text: result.text);
  }

  /// Up to 3 OTHER nearby forest locations, for color/context only (spec
  /// §6: "combine multiple facts into one story") — plain distance
  /// sorting, the same math every other forest feature already uses, not
  /// a new ranking system.
  List<String> _nearbySummaryExcluding(String excludeId, double lat, double lng) {
    final others = [
      for (final l in _locations)
        if (l.id != excludeId && l.active) l,
    ];
    others.sort((a, b) => GeoMath.distanceMeters(lat, lng, a.latitude, a.longitude)
        .compareTo(GeoMath.distanceMeters(lat, lng, b.latitude, b.longitude)));
    return [
      for (final l in others.take(3))
        '${l.name} (${l.category}, ${(GeoMath.distanceMeters(lat, lng, l.latitude, l.longitude) / 1609.344).toStringAsFixed(1)}mi)',
    ];
  }

  Future<void> _playAudio({required String title, String? audioUrl, String? text}) {
    return ref.read(forestAudioControllerProvider.notifier).play(
          title: title,
          audioUrl: audioUrl,
          spokenText: audioUrl == null ? text : null,
        );
  }

  void pause() => ref.read(forestAudioControllerProvider.notifier).pause();
  void resume() => ref.read(forestAudioControllerProvider.notifier).resume();
  void replay() => ref.read(forestAudioControllerProvider.notifier).replay();

  Future<void> endTour() async {
    state = state.copyWith(status: TourStatus.ended, loading: false, clearError: true);
    await ref.read(forestAudioControllerProvider.notifier).stop();
  }
}

final forestTourControllerProvider =
    NotifierProvider<ForestTourController, ForestTourState>(ForestTourController.new);
