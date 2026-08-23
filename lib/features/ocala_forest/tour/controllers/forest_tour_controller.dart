import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
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

class ForestTourState {
  const ForestTourState({
    this.status = TourStatus.idle,
    this.tourType = TourType.general,
    this.currentSubjectName,
    this.currentText,
    this.currentStoryType = TourStoryType.general,
    this.loading = false,
    this.error,
    this.segmentsPlayed = 0,
  });

  final TourStatus status;
  final TourType tourType;
  final String? currentSubjectName;
  final String? currentText;
  final TourStoryType currentStoryType;
  final bool loading;
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
        error: clearError ? null : (error ?? this.error),
        segmentsPlayed: segmentsPlayed ?? this.segmentsPlayed,
      );
}

/// "Take Me On A Tour" (spec §1) — orchestrates EXISTING infrastructure
/// only: GPS (`gpsControllerProvider`), the existing forest
/// locations/trails data, [ForestTourEngine] (which itself wraps the same
/// `LocationTriggerEngine`/`nearestTrailId` every other forest feature
/// already uses — no new geofence/location system), the `forest-tour` Edge
/// Function (OpenAI + ElevenLabs, the SAME integrations copilot-line/
/// forest-discovery/forest-trail-audio already use), and
/// [ForestAudioController] (the SAME dedicated forest audio player, so
/// this tour's audio can never fight the radio — spec §15).
///
/// "Tour history" (spec §16) is a plain in-memory `Set`/`List` scoped to
/// one tour — the "simplest appropriate approach" the spec asks for, given
/// this app has no real per-user account system to hang persistent history
/// off of. Swapping this for `shared_preferences`-backed persistence later
/// (already a dependency, already used elsewhere) is a small, contained
/// change to just these two fields, not a redesign.
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
    ForestLocation? anchorLocation, // future QR compat (spec §19) — start already-focused on one location
  }) async {
    _discussedIds.clear();
    _discussedNames.clear();
    _locations = ref.read(forestLocationsProvider).value ?? const [];
    _trails = ref.read(forestTrailsProvider).value ?? const [];
    _forest = ref.read(ocalaForestBoundaryProvider).value;

    state = ForestTourState(status: TourStatus.active, tourType: tourType, loading: true);

    if (!_wired) {
      _wired = true;
      ref.listen<TravelContext>(gpsControllerProvider, (_, ctx) {
        if (!state.isActive) return;
        _handleMovement(ctx);
      });
    }

    final narration = ref.read(forestTourNarrationServiceProvider);
    final intro = await narration.requestIntro(forest: _forest);
    if (!state.isActive) return; // ended while awaiting
    if (intro == null) {
      state = state.copyWith(loading: false, error: "Couldn't start the tour — check your connection and try again.");
      return;
    }
    state = state.copyWith(
      loading: false,
      currentSubjectName: _forest?.name ?? 'Ocala National Forest',
      currentText: intro.text,
      currentStoryType: TourStoryType.general,
      segmentsPlayed: 1,
    );
    await _playAudio(title: '🎧 Tour Introduction', audioUrl: intro.audioUrl, text: intro.text);

    if (anchorLocation != null) {
      await _playSubject(TourSubject.forLocation(anchorLocation));
    } else {
      _handleMovement(ref.read(gpsControllerProvider));
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
    if (subject == null) return; // spec §9: stay quiet, this is normal
    _playSubject(subject);
  }

  /// "🎙️ Tell Me Something" (spec §11) and "⏭️ Next Story" (spec §10) —
  /// both an explicit, on-demand request for a new subject right now,
  /// bypassing the movement cooldown (the visitor asked directly) but
  /// still respecting the anti-repeat history.
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
    await _playSubject(subject);
  }

  Future<void> nextStory() => tellMeSomething();

  Future<void> _playSubject(TourSubject subject) async {
    state = state.copyWith(loading: true, clearError: true);
    final narration = ref.read(forestTourNarrationServiceProvider);
    final result = await narration.requestForSubject(
      subject,
      forest: _forest,
      recentlyMentioned: List.unmodifiable(_discussedNames),
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
