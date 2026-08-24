import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/navigation/models/route_plan.dart';
import 'package:explorer_os_mobile/features/navigation/models/trip_progress.dart';
import 'package:explorer_os_mobile/features/navigation/services/trip_tracker.dart';

class MissionRouteState {
  const MissionRouteState({this.route, this.progress = TripProgress.idleState, this.loading = false});
  final RoutePlan? route;
  final TripProgress progress;
  final bool loading;

  MissionRouteState copyWith({RoutePlan? route, TripProgress? progress, bool? loading}) =>
      MissionRouteState(
        route: route ?? this.route,
        progress: progress ?? this.progress,
        loading: loading ?? this.loading,
      );
}

/// Real road routing for the journey map — a fresh, self-contained
/// [TripTracker] instance (the SAME class, DirectionsClient, and Google
/// Directions integration `StartTripButton`'s existing navigation feature
/// already uses), owned independently rather than sharing that feature's
/// `tripControllerProvider` singleton, so the two never interfere with each
/// other. Feeds it the SAME live GPS stream every other location-aware
/// feature reads ([gpsControllerProvider]) — no second GPS system, no new
/// routing integration, just another consumer of an existing reusable
/// class.
class MissionRouteController extends Notifier<MissionRouteState> {
  TripTracker? _tracker;
  StreamSubscription<TripEvent>? _eventSub;
  double? _destLat;
  double? _destLng;

  @override
  MissionRouteState build() {
    ref.listen<TravelContext>(gpsControllerProvider, (_, ctx) {
      final loc = ctx.location;
      if (loc != null) _tracker?.onLocation(loc);
    });
    ref.onDispose(() {
      _eventSub?.cancel();
      _tracker?.dispose();
    });
    return const MissionRouteState();
  }

  /// Starts (or re-targets) routing toward a destination. A no-op if
  /// already routing to the exact same point — cheap to call on every
  /// build without re-fetching the route each time.
  Future<void> routeTo({
    required double lat,
    required double lng,
    required String name,
  }) async {
    if (_destLat == lat && _destLng == lng) return;
    _destLat = lat;
    _destLng = lng;

    final gps = ref.read(gpsControllerProvider).location;
    if (gps == null) return; // retried by the widget once a fix arrives

    _eventSub?.cancel();
    _tracker?.dispose();
    final tracker = TripTracker();
    _tracker = tracker;
    _eventSub = tracker.events.listen((_) => _sync());

    state = state.copyWith(loading: true);
    await tracker.start(
      originLat: gps.latitude,
      originLng: gps.longitude,
      destinationLat: lat,
      destinationLng: lng,
      destinationName: name,
    );
    _sync();
  }

  void stop() {
    _eventSub?.cancel();
    _tracker?.dispose();
    _tracker = null;
    _destLat = null;
    _destLng = null;
    state = const MissionRouteState();
  }

  void _sync() {
    state = MissionRouteState(
      route: _tracker?.route,
      progress: _tracker?.progress ?? TripProgress.idleState,
      loading: false,
    );
  }
}

final missionRouteControllerProvider =
    NotifierProvider<MissionRouteController, MissionRouteState>(MissionRouteController.new);
