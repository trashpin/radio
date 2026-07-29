import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/core/utils/temporal.dart';
import 'package:explorer_os_mobile/features/around_me/logic/anti_repeat_tracker.dart';
import 'package:explorer_os_mobile/features/around_me/logic/around_me_detector.dart';
import 'package:explorer_os_mobile/features/around_me/logic/around_me_events.dart';
import 'package:explorer_os_mobile/features/around_me/logic/explorer_score.dart';
import 'package:explorer_os_mobile/features/around_me/models/experience.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/events/gps_event.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_providers.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Distance within which a POI is considered "entered" (drives EnteredPoi/
/// ExitedPoi events). Independent of the wider Around Me search radius.
const double poiTriggerMeters = 120;

/// Experiences the visitor has saved (local, in-memory for now).
final savedExperiencesProvider =
    NotifierProvider<SavedExperiences, Set<String>>(SavedExperiences.new);

class SavedExperiences extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};
  void toggle(String id) {
    final next = Set<String>.of(state);
    if (!next.add(id)) next.remove(id);
    state = next;
  }

  bool contains(String id) => state.contains(id);
}

/// Experiences the visitor has already been near/visited (deprioritized).
final visitedExperiencesProvider =
    NotifierProvider<VisitedExperiences, Set<String>>(VisitedExperiences.new);

class VisitedExperiences extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};
  void add(String id) {
    if (state.contains(id)) return;
    state = {...state, id};
  }
}

/// Experiences whose narration has already been played (deprioritized).
final playedNarrationIdsProvider =
    NotifierProvider<PlayedNarrations, Set<String>>(PlayedNarrations.new);

class PlayedNarrations extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};
  void add(String id) {
    if (state.contains(id)) return;
    state = {...state, id};
  }
}

/// The visitor's current guide preference — a category token they lean toward
/// (e.g. `wildlife`, `historic_sites`). `null` = no preference.
final guidePreferenceProvider =
    NotifierProvider<GuidePreference, String?>(GuidePreference.new);

class GuidePreference extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? token) => state = token;
}

/// Lifetime anti-repeat bookkeeping (shared across the session).
final antiRepeatTrackerProvider =
    Provider<AntiRepeatTracker>((ref) => AntiRepeatTracker());

/// The scored, sorted list of nearby experiences (the Around Me feed).
///
/// Pulls `map_locations` content, filters to the current search radius around
/// the live GPS position, and ranks by [explorerScore] — so the most
/// interesting nearby experiences surface first (not merely the closest).
final aroundMeExperiencesProvider = Provider<List<Experience>>((ref) {
  final ctx = ref.watch(gpsControllerProvider);
  final loc = ctx.location;
  if (loc == null) return const [];
  final radius = ref.watch(searchRadiusProvider);
  final items = ref.watch(mapLocationsProvider).value ?? const <NearbyItem>[];
  final visited = ref.watch(visitedExperiencesProvider);
  final played = ref.watch(playedNarrationIdsProvider);
  final guide = ref.watch(guidePreferenceProvider);

  Experience build(NearbyItem item, double dist, double scoreRadius) {
    final bearing = GeoMath.bearingDegrees(
        loc.latitude, loc.longitude, item.latitude, item.longitude);
    final input = ExplorerScoreInput(
      distanceMeters: dist,
      radiusMeters: scoreRadius,
      featured: item.featured,
      recommended: item.featured,
      seasonRelevance: _seasonRelevance(item.category, ctx.season),
      timeOfDayRelevance: _timeRelevance(item.category, ctx.timeOfDay),
      guidePreference: _guideMatch(item.category, guide),
      previouslyVisited: visited.contains(item.id),
      narrationAlreadyPlayed: played.contains(item.id),
    );
    return Experience(
      id: item.id,
      name: item.name,
      category: item.category,
      subcategory: item.subcategory,
      description: item.description,
      imageUrl: item.imageUrl,
      audioUrl: item.audioUrl,
      latitude: item.latitude,
      longitude: item.longitude,
      featured: item.featured,
      distanceMeters: dist,
      bearingDegrees: bearing,
      score: explorerScore(input),
      visited: visited.contains(item.id),
      narrationPlayed: played.contains(item.id),
    );
  }

  // Distance to every valid item, once.
  final withDist = <(NearbyItem, double)>[];
  for (final item in items) {
    if (item.latitude == 0 && item.longitude == 0) continue;
    withDist.add((
      item,
      GeoMath.distanceMeters(
          loc.latitude, loc.longitude, item.latitude, item.longitude),
    ));
  }

  final out = <Experience>[
    for (final (item, dist) in withDist)
      if (dist <= radius.meters) build(item, dist, radius.meters),
  ];
  out.sort((a, b) => b.score.compareTo(a.score));

  // Fallback: in sparse/rural areas nothing may fall inside the chosen radius.
  // Always surface the nearest notable places (up to ~25 mi) so "What's Near
  // Me?" is never empty and shows things like nearby lakes, parks & springs.
  if (out.length < 5) {
    const fallbackCapM = 40233.0; // 25 miles
    final have = out.map((e) => e.id).toSet();
    final extra = [
      for (final (item, dist) in withDist)
        if (dist > radius.meters && dist <= fallbackCapM && !have.contains(item.id))
          (item, dist),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    for (final (item, dist) in extra.take(10 - out.length)) {
      out.add(build(item, dist, fallbackCapM));
    }
  }
  return out.length > 60 ? out.sublist(0, 60) : out;
});

/// An immutable snapshot of the visitor's surroundings for the UI / debug panel.
class AroundMeSnapshot {
  const AroundMeSnapshot({
    this.latitude,
    this.longitude,
    this.headingDegrees,
    this.speedMps = 0,
    this.accuracyMeters,
    this.altitudeMeters,
    this.movement = MovementState.idle,
    this.travelMode = TravelMode.stationary,
    this.zone,
    this.currentDestination,
    this.radius = SearchRadius.mi1,
    this.nearbyCount = 0,
    this.gpsAvailable = false,
    this.status = GpsTrackingStatus.idle,
    this.lastEvent,
  });

  final double? latitude;
  final double? longitude;
  final double? headingDegrees;
  final double speedMps;
  final double? accuracyMeters;
  final double? altitudeMeters;
  final MovementState movement;
  final TravelMode travelMode;
  final String? zone;
  final String? currentDestination;
  final SearchRadius radius;
  final int nearbyCount;
  final bool gpsAvailable;
  final GpsTrackingStatus status;
  final AroundMeEvent? lastEvent;

  double get speedMph => speedMps * 2.2369362921;
}

/// The Around Me coordinator: watches the live GPS engine, mirrors position to
/// the shared map center, derives [AroundMeEvent]s via [AroundMeDetector], and
/// publishes a [AroundMeSnapshot]. Emits events only — it never plays audio.
final aroundMeControllerProvider =
    NotifierProvider<AroundMeController, AroundMeSnapshot>(
        AroundMeController.new);

/// Stream of Around Me events (the Playback Manager will subscribe in a later
/// phase). GPS/Around Me only detects and emits — never plays.
final aroundMeEventsProvider = StreamProvider<AroundMeEvent>((ref) {
  return ref.watch(aroundMeControllerProvider.notifier).events;
});

class AroundMeController extends Notifier<AroundMeSnapshot> {
  final AroundMeDetector _detector = AroundMeDetector();
  final StreamController<AroundMeEvent> _events =
      StreamController<AroundMeEvent>.broadcast();
  bool _gpsAvailable = true;
  AroundMeEvent? _lastEvent;
  StreamSubscription<GpsEvent>? _gpsEventsSub;

  Stream<AroundMeEvent> get events => _events.stream;

  @override
  AroundMeSnapshot build() {
    ref.onDispose(_events.close);

    // React to each new travel context (position/heading/speed/movement/zone).
    ref.listen<TravelContext>(gpsControllerProvider, (_, next) {
      _mirrorCenter(next);
      _recompute();
    });

    // Recompute when the search radius or content set changes.
    ref.listen(searchRadiusProvider, (_, _) => _recompute());
    ref.listen(mapLocationsProvider, (_, _) => _recompute());

    // Track GPS availability via the engine's lost/recovered events.
    final service = ref.read(gpsServiceProvider);
    _gpsEventsSub = service.events.listen((e) {
      if (e is GpsLost) {
        _gpsAvailable = false;
        _recompute();
      } else if (e is GpsRecovered) {
        _gpsAvailable = true;
        _recompute();
      }
    });
    ref.onDispose(() => _gpsEventsSub?.cancel());

    // Run an initial detection once the notifier's state is initialized.
    Future.microtask(() {
      _mirrorCenter(ref.read(gpsControllerProvider));
      _recompute();
    });

    return _buildSnapshot();
  }

  void _mirrorCenter(TravelContext ctx) {
    final loc = ctx.location;
    if (loc == null) return;
    ref.read(mapCenterProvider.notifier).set(LatLng(loc.latitude, loc.longitude));
  }

  void _recompute() {
    final ctx = ref.read(gpsControllerProvider);
    final experiences = ref.read(aroundMeExperiencesProvider);

    final nearby = experiences
        .map<NearbyRef>((e) => (
              id: e.id,
              name: e.name,
              distanceMeters: e.distanceMeters,
              isTrail: e.isTrail,
            ))
        .toList(growable: false);

    final produced = _detector.update(
      now: ctx.location?.timestamp ?? DateTime.now(),
      nearby: nearby,
      triggerRadiusMeters: poiTriggerMeters,
      movement: ctx.movementState,
      zone: ctx.currentParkId,
      gpsAvailable: _gpsAvailable && ctx.location != null,
    );

    for (final event in produced) {
      _events.add(event);
      _lastEvent = event;
      // Entering a POI marks it visited so the feed adapts as you explore.
      if (event is EnteredPoi) {
        ref.read(visitedExperiencesProvider.notifier).add(event.id);
      }
    }

    state = _buildSnapshot(ctx: ctx, experiences: experiences);
  }

  AroundMeSnapshot _buildSnapshot({
    TravelContext? ctx,
    List<Experience>? experiences,
  }) {
    final TravelContext c = ctx ?? ref.read(gpsControllerProvider);
    final List<Experience> exp =
        experiences ?? ref.read(aroundMeExperiencesProvider);
    final loc = c.location;
    return AroundMeSnapshot(
      latitude: loc?.latitude,
      longitude: loc?.longitude,
      headingDegrees: c.bearingDegrees ?? loc?.headingDegrees,
      speedMps: c.speed?.metersPerSecond ?? 0,
      accuracyMeters: loc?.accuracyMeters,
      altitudeMeters: c.altitudeMeters ?? loc?.elevationMeters,
      movement: c.movementState,
      travelMode: c.travelMode,
      zone: c.currentParkId,
      currentDestination: c.currentParkId,
      radius: ref.read(searchRadiusProvider),
      nearbyCount: exp.length,
      gpsAvailable: _gpsAvailable && loc != null,
      status: ref.read(gpsServiceProvider).status,
      lastEvent: _lastEvent,
    );
  }

  /// Marks a narration as played (called when the user taps Play Narration or
  /// when the Playback Manager plays a POI clip). Updates anti-repeat + scoring.
  void markNarrationPlayed(String id) {
    final loc = ref.read(gpsControllerProvider).location;
    ref.read(antiRepeatTrackerProvider).markPlayed(
          id,
          now: DateTime.now(),
          latitude: loc?.latitude ?? 0,
          longitude: loc?.longitude ?? 0,
        );
    ref.read(playedNarrationIdsProvider.notifier).add(id);
  }
}

// --- Relevance helpers -------------------------------------------------------

/// Light seasonal relevance so the Explorer Score genuinely reflects the season
/// (neutral 0.5 for categories with no strong seasonal signal).
double _seasonRelevance(String category, Season season) {
  final c = category.toLowerCase();
  switch (season) {
    case Season.spring:
      if (c.contains('wildflower') || c.contains('bird')) return 1.0;
    case Season.summer:
      if (c.contains('spring') || c.contains('water') || c.contains('swim')) {
        return 1.0;
      }
    case Season.autumn:
      if (c.contains('tree') || c.contains('trail')) return 0.85;
    case Season.winter:
      if (c.contains('historic') || c.contains('visitor')) return 0.8;
  }
  return 0.5;
}

/// Light time-of-day relevance (neutral 0.5 otherwise).
double _timeRelevance(String category, TimeOfDayBucket tod) {
  final c = category.toLowerCase();
  switch (tod) {
    case TimeOfDayBucket.earlyMorning:
    case TimeOfDayBucket.morning:
      if (c.contains('bird') || c.contains('wildlife') || c.contains('trail')) {
        return 1.0;
      }
    case TimeOfDayBucket.afternoon:
      if (c.contains('spring') || c.contains('water')) return 0.9;
    case TimeOfDayBucket.evening:
      if (c.contains('scenic') || c.contains('photo') || c.contains('overlook')) {
        return 1.0;
      }
    case TimeOfDayBucket.night:
      if (c.contains('camp')) return 0.9;
  }
  return 0.5;
}

/// Guide preference match: strong when it matches, neutral when unset, mild
/// penalty when it clearly doesn't.
double _guideMatch(String category, String? preference) {
  if (preference == null || preference.isEmpty) return 0.5;
  return category.toLowerCase().contains(preference.toLowerCase()) ? 1.0 : 0.3;
}
