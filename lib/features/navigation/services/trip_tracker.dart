import 'dart:async';
import 'dart:math' as math;

import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/navigation/models/route_plan.dart';
import 'package:explorer_os_mobile/features/navigation/models/trip_progress.dart';
import 'package:explorer_os_mobile/features/navigation/services/directions_client.dart';

/// The shape of "fetch a route" — matches [DirectionsClient.route] exactly.
/// `TripTracker` depends on this function type rather than the concrete
/// client so tests can inject a fake route directly, without needing to
/// satisfy [DirectionsClient]'s own `EnvConfig.hasGoogleMapsApiKey` gate
/// (the same reason `driving_distance_service_test.dart` only tests that
/// service's pure JSON parser rather than its env-gated network method).
typedef RouteFetcher = Future<RoutePlan?> Function({
  required double originLat,
  required double originLng,
  required double destinationLat,
  required double destinationLng,
  String? destinationName,
});

/// Background route tracker — no map, no turn-arrow UI. Fetches a route via
/// a [RouteFetcher] (by default [DirectionsClient.route]), then on every GPS
/// fix works out which step the traveler is on, how far to the next
/// maneuver, whether they've drifted off the route (and if so, re-fetches a
/// fresh route — "recalculating"), and whether they've arrived. Emits
/// [TripEvent]s for the Copilot Brain to react to; plays nothing itself and
/// owns no audio.
///
/// Deliberately separate from the existing `RouteEngine`
/// (`lib/features/gps/services/route_engine.dart`), which tracks progress
/// against an ordered list of attraction stops for ETA/cumulative-distance
/// purposes — a different job with a different shape. This class is the only
/// thing in the app that understands turn-by-turn maneuvers, because nothing
/// else needed to before.
class TripTracker {
  TripTracker({RouteFetcher? fetchRoute})
      : _fetchRoute = fetchRoute ?? DirectionsClient().route;

  final RouteFetcher _fetchRoute;

  /// Consecutive off-route fixes beyond this distance before recalculating —
  /// avoids a single noisy GPS fix triggering a false "recalculating".
  static const double offRouteThresholdMeters = 60;
  static const int offRouteStreakToTrigger = 3;

  /// "Approaching a turn" fires once the next maneuver is this close.
  static const double approachThresholdMeters = 400; // ~0.25 mile

  static const double arrivalRadiusMeters = 40;

  /// A step is considered "passed" once the traveler is this close to its
  /// end point — short enough to not skip steps early, long enough to
  /// tolerate ordinary GPS jitter at the corner of a turn.
  static const double maneuverPassedToleranceMeters = 25;

  RoutePlan? _route;
  double? _destLat;
  double? _destLng;
  String? _destName;
  int _stepIndex = 0;
  int? _lastAnnouncedStepIndex;
  int _offRouteStreak = 0;
  bool _recalculating = false;

  TripProgress _progress = TripProgress.idleState;
  TripProgress get progress => _progress;
  RoutePlan? get route => _route;

  final _controller = StreamController<TripEvent>.broadcast();
  Stream<TripEvent> get events => _controller.stream;

  /// Fetches a route and starts tracking. No-ops (progress stays idle) if
  /// Directions can't produce a route — never leaves a half-started trip.
  Future<void> start({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    String? destinationName,
  }) async {
    _destLat = destinationLat;
    _destLng = destinationLng;
    _destName = destinationName;
    _stepIndex = 0;
    _lastAnnouncedStepIndex = null;
    _offRouteStreak = 0;
    _recalculating = false;

    final plan = await _fetchRoute(
      originLat: originLat,
      originLng: originLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      destinationName: destinationName,
    );
    if (plan == null || plan.isEmpty) {
      _route = null;
      _progress = TripProgress.idleState;
      return;
    }
    _route = plan;
    _progress = TripProgress(
      status: TripStatus.onRoute,
      destinationName: destinationName,
      distanceRemainingMeters: plan.totalDistanceMeters,
    );
    _controller.add(TripStarted(destinationName));
  }

  void cancel() {
    if (_progress.status == TripStatus.idle) return;
    _route = null;
    _progress = TripProgress.idleState;
    _controller.add(const TripEnded());
  }

  /// Call once per GPS fix while a trip is active. No-ops when idle/arrived.
  Future<void> onLocation(GPSLocation loc) async {
    final route = _route;
    final destLat = _destLat;
    final destLng = _destLng;
    if (route == null || destLat == null || destLng == null) return;
    if (!_progress.isActive) return;

    final distToDest =
        GeoMath.distanceMeters(loc.latitude, loc.longitude, destLat, destLng);
    if (distToDest <= arrivalRadiusMeters) {
      _route = null;
      _progress = _progress.copyWith(
        status: TripStatus.arrived,
        distanceRemainingMeters: 0,
      );
      _controller.add(const TripArrived());
      return;
    }

    // Advance past any step(s) whose end point we've already reached.
    var idx = _stepIndex;
    while (idx < route.steps.length - 1) {
      final end = route.steps[idx];
      final distToEnd = GeoMath.distanceMeters(
          loc.latitude, loc.longitude, end.endLat, end.endLng);
      if (distToEnd <= maneuverPassedToleranceMeters) {
        idx++;
      } else {
        break;
      }
    }
    final advanced = idx != _stepIndex;
    _stepIndex = idx;

    final currentStep = route.steps[_stepIndex];
    final distToManeuver = GeoMath.distanceMeters(
        loc.latitude, loc.longitude, currentStep.endLat, currentStep.endLng);

    final offRoute = _distanceToPolyline(loc.latitude, loc.longitude, route.polyline);
    _offRouteStreak = offRoute > offRouteThresholdMeters ? _offRouteStreak + 1 : 0;

    if (_offRouteStreak >= offRouteStreakToTrigger && !_recalculating) {
      _recalculating = true;
      _progress =
          _progress.copyWith(status: TripStatus.recalculating, offRouteMeters: offRoute);
      // A "missed turn" is off-route detected right at a maneuver point
      // rather than somewhere in the middle of a long step — a reasonable
      // heuristic given there's no lane-level map matching in this feature.
      final justPassedManeuver =
          !advanced && distToManeuver <= offRouteThresholdMeters * 2;
      _controller.add(justPassedManeuver ? const MissedTurn() : const Recalculating());

      final fresh = await _fetchRoute(
        originLat: loc.latitude,
        originLng: loc.longitude,
        destinationLat: destLat,
        destinationLng: destLng,
        destinationName: _destName,
      );
      _recalculating = false;
      _offRouteStreak = 0;
      if (fresh != null && !fresh.isEmpty) {
        _route = fresh;
        _stepIndex = 0;
        _lastAnnouncedStepIndex = null;
        _progress = _progress.copyWith(
          status: TripStatus.onRoute,
          currentStepIndex: 0,
          distanceRemainingMeters: fresh.totalDistanceMeters,
        );
      } else {
        // Recalculation failed — stay on the stale route rather than going
        // silent; a stale instruction beats no guidance at all.
        _progress = _progress.copyWith(status: TripStatus.onRoute);
      }
      return;
    }

    _progress = _progress.copyWith(
      status: TripStatus.onRoute,
      currentStepIndex: _stepIndex,
      distanceToManeuverMeters: distToManeuver,
      offRouteMeters: offRoute,
      distanceRemainingMeters: distToDest,
    );

    final shouldAnnounce = distToManeuver <= approachThresholdMeters &&
        _lastAnnouncedStepIndex != _stepIndex;
    if (shouldAnnounce) {
      _lastAnnouncedStepIndex = _stepIndex;
      _controller.add(ApproachingManeuver(currentStep, distToManeuver));
    }
  }

  double _distanceToPolyline(
    double lat,
    double lng,
    List<({double lat, double lng})> poly,
  ) {
    if (poly.length < 2) return 0;
    var best = double.infinity;
    for (var i = 0; i < poly.length - 1; i++) {
      final d = _distanceToSegment(
        lat,
        lng,
        poly[i].lat,
        poly[i].lng,
        poly[i + 1].lat,
        poly[i + 1].lng,
      );
      if (d < best) best = d;
    }
    return best;
  }

  /// Perpendicular distance from a point to a segment, treating the small
  /// local area around the segment as flat — accurate enough at the scale of
  /// a single route step, far simpler than full geodesic segment math.
  double _distanceToSegment(
    double plat,
    double plng,
    double alat,
    double alng,
    double blat,
    double blng,
  ) {
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos(alat * math.pi / 180.0);
    final px = (plng - alng) * mPerDegLng;
    final py = (plat - alat) * mPerDegLat;
    final bx = (blng - alng) * mPerDegLng;
    final by = (blat - alat) * mPerDegLat;
    final segLenSq = bx * bx + by * by;
    if (segLenSq == 0) {
      return GeoMath.distanceMeters(plat, plng, alat, alng);
    }
    final t = ((px * bx + py * by) / segLenSq).clamp(0.0, 1.0);
    final dx = px - bx * t;
    final dy = py - by * t;
    return math.sqrt(dx * dx + dy * dy);
  }

  void dispose() => _controller.close();
}
