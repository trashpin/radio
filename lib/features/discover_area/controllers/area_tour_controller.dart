import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/models/nearby_attractions.dart';
import 'package:explorer_os_mobile/features/discover_area/models/tour_mode.dart';
import 'package:explorer_os_mobile/features/gps/services/location_trigger_engine.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart'
    show locationContextProvider;
import 'package:explorer_os_mobile/features/location_intelligence/location_intelligence.dart'
    show LocationContext;
import 'package:explorer_os_mobile/features/radio/discovery/nearby_narration_controller.dart';

/// State of an in-progress Driving/Walking tour.
class AreaTourState {
  const AreaTourState({
    this.stops = const [],
    this.visitedIds = const {},
    this.running = false,
  });

  final List<AttractionMatch> stops;
  final Set<String> visitedIds;
  final bool running;

  int get visitedCount => visitedIds.length;
  bool isVisited(AttractionMatch m) => visitedIds.contains(m.location.id);

  AreaTourState copyWith({Set<String>? visitedIds, bool? running}) => AreaTourState(
        stops: stops,
        visitedIds: visitedIds ?? this.visitedIds,
        running: running ?? this.running,
      );
}

/// Drives a Driving/Walking tour: as the traveler's live GPS position enters
/// a stop's proximity radius (see [TourMode]), that stop narrates
/// automatically via [NearbyNarrationController.narrateLocation] — the exact
/// mechanism the app already uses for any Master Location — and is marked
/// visited. Built almost entirely on two things that already existed before
/// this phase: [LocationTriggerEngine] (GPS arrival detection) and
/// [NearbyNarrationController] (narration playback).
class AreaTourController extends Notifier<AreaTourState> {
  final _engine = LocationTriggerEngine();
  bool _wired = false;
  TourMode _mode = TourMode.driving;

  @override
  AreaTourState build() {
    ref.onDispose(() => ref.read(nearbyNarrationControllerProvider.notifier).clear());
    return const AreaTourState();
  }

  /// Begins the tour: [stops] narrate automatically as the traveler
  /// physically nears each one, using [mode]'s trigger radius. Safe to call
  /// again to restart with a new stop list — the GPS listener itself is
  /// only ever registered once.
  void start(List<AttractionMatch> stops, TourMode mode) {
    _mode = mode;
    state = AreaTourState(stops: stops, running: true);
    if (!_wired) {
      _wired = true;
      ref.listen<LocationContext>(locationContextProvider, (_, ctx) {
        if (!state.running) return;
        _handle(ctx, _mode);
      });
    }
    // Evaluate immediately against the current fix too, not just future ones.
    _handle(ref.read(locationContextProvider), mode);
  }

  void _handle(LocationContext ctx, TourMode mode) {
    if (ctx.latitude == 0 && ctx.longitude == 0) return; // no GPS fix yet
    final candidates = [
      for (final s in state.stops)
        TriggerableLocation(
          id: s.location.id,
          latitude: s.location.latitude!,
          longitude: s.location.longitude!,
          radiusMeters: mode.triggerRadiusMeters,
        ),
    ];
    final events = _engine.evaluate(ctx.latitude, ctx.longitude, candidates);
    for (final e in events) {
      if (e.kind != LocationTriggerKind.arrival) continue;
      final stop = state.stops.firstWhere((s) => s.location.id == e.locationId);
      state = state.copyWith(visitedIds: {...state.visitedIds, stop.location.id});
      ref.read(nearbyNarrationControllerProvider.notifier).narrateLocation(stop.location);
    }
  }

  /// Ends the tour early (also called automatically on dispose).
  void stop() {
    state = state.copyWith(running: false);
    ref.read(nearbyNarrationControllerProvider.notifier).clear();
  }
}

final areaTourControllerProvider =
    NotifierProvider<AreaTourController, AreaTourState>(AreaTourController.new);
