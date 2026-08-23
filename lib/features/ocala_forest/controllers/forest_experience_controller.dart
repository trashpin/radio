import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/services/location_trigger_engine.dart';
import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_audio_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';

/// Default geofence radius for a forest location with none set — matches
/// the same fallback POI trigger radius used elsewhere in the app.
const double kForestDefaultGeofenceMeters = 150;

/// One arrival at a forest location, produced by [ForestExperienceEngine].
class ForestArrival {
  const ForestArrival(this.location);
  final ForestLocation location;
}

/// Pure GPS-arrival detection for forest locations — no Riverpod, no audio,
/// no I/O, so it's directly unit-testable (mirrors the existing
/// `TripTracker`/`TripController` split: the algorithm lives in a plain
/// class, the Notifier below is a thin Riverpod wrapper around it). Wraps
/// the existing, generic `LocationTriggerEngine` (the same one
/// `_attachLocationTriggers` and `AreaTourController` already use for
/// Marion content) — no new geofence detector was written.
class ForestExperienceEngine {
  final _trigger = LocationTriggerEngine();

  /// Feeds one GPS fix against every active, geofence-triggered
  /// [locations]. Returns every location newly arrived at this fix.
  List<ForestArrival> onLocation(
    GPSLocation fix,
    List<ForestLocation> locations, {
    DateTime? now,
  }) {
    final candidates = [
      for (final l in locations)
        if (l.active && l.triggerType == 'geofence')
          TriggerableLocation(
            id: l.id,
            latitude: l.latitude,
            longitude: l.longitude,
            radiusMeters: l.geofenceRadiusMeters ?? kForestDefaultGeofenceMeters,
          ),
    ];
    final events =
        _trigger.evaluate(fix.latitude, fix.longitude, candidates, now: now);

    final arrivals = <ForestArrival>[];
    for (final e in events) {
      if (e.kind != LocationTriggerKind.arrival) continue;
      for (final l in locations) {
        if (l.id == e.locationId) {
          arrivals.add(ForestArrival(l));
          break;
        }
      }
    }
    return arrivals;
  }
}

class ForestExperienceState {
  const ForestExperienceState({this.visitedIds = const {}, this.running = false});
  final Set<String> visitedIds;
  final bool running;

  ForestExperienceState copyWith({Set<String>? visitedIds, bool? running}) =>
      ForestExperienceState(
        visitedIds: visitedIds ?? this.visitedIds,
        running: running ?? this.running,
      );
}

/// Drives GPS/geofence-triggered forest experiences: as the traveler's live
/// position enters a [ForestLocation]'s geofence radius
/// ([ForestExperienceEngine]), its narration plays automatically via the
/// dedicated [ForestAudioController] (never the shared Radio Engine — see
/// that controller's doc comment for why) and it's marked visited. This is
/// the "Experience layer" the spec asks for.
///
/// One shared instance covers every forest location regardless of which
/// experience screen (Trails, Discoveries) is open, so two engines never
/// double-fire on the same location. Started when the Ocala Forest
/// Explorer hub mounts, stopped on dispose — scoped to "while the user is
/// in this isolated experiment," not a permanent background service.
class ForestExperienceController extends Notifier<ForestExperienceState> {
  final _engine = ForestExperienceEngine();
  bool _wired = false;
  List<ForestLocation> _locations = const [];

  @override
  ForestExperienceState build() => const ForestExperienceState();

  void start() {
    state = state.copyWith(running: true);
    _locations = ref.read(forestLocationsProvider).value ?? const [];
    if (!_wired) {
      _wired = true;
      ref.listen<TravelContext>(gpsControllerProvider, (_, ctx) {
        if (!state.running) return;
        _handle(ctx);
      });
    }
    _handle(ref.read(gpsControllerProvider));
  }

  void stop() {
    state = state.copyWith(running: false);
  }

  void _handle(TravelContext ctx) {
    final fix = ctx.location;
    if (fix == null) return;
    final arrivals = _engine.onLocation(fix, _locations);
    for (final arrival in arrivals) {
      final loc = arrival.location;
      state = state.copyWith(visitedIds: {...state.visitedIds, loc.id});
      _play(loc);
    }
  }

  void _play(ForestLocation loc) {
    final text = (loc.narrationShort ?? '').trim();
    ref.read(forestAudioControllerProvider.notifier).play(
          title: loc.name,
          audioUrl: loc.hasAudio ? loc.audioUrl : null,
          spokenText: loc.hasAudio ? null : (text.isNotEmpty ? text : "You're near ${loc.name}."),
        );
  }
}

final forestExperienceControllerProvider =
    NotifierProvider<ForestExperienceController, ForestExperienceState>(
        ForestExperienceController.new);
