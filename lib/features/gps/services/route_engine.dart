import 'package:explorer_os_mobile/features/gps/models/attraction_point.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/route_progress.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Tracks distance travelled and progress toward the next stop on a route.
///
/// WHY THIS EXISTS: cumulative distance and "next stop + ETA" are journey-level
/// signals distinct from raw proximity. This service accumulates distance from
/// consecutive fixes and computes [RouteProgress] against an optional ordered
/// itinerary — all offline (no map SDK / directions API required).
class RouteEngine {
  String? _routeId;
  final List<AttractionPoint> _stops = [];
  double _distanceTravelledMeters = 0;
  GPSLocation? _last;

  double get distanceTravelledMeters => _distanceTravelledMeters;

  void setRoute({String? routeId, List<AttractionPoint> stops = const []}) {
    _routeId = routeId;
    _stops
      ..clear()
      ..addAll(stops);
  }

  void reset() {
    _distanceTravelledMeters = 0;
    _last = null;
  }

  /// Accumulate distance as the user moves. Call once per fix.
  void onLocation(GPSLocation loc) {
    if (_last != null) {
      _distanceTravelledMeters += GeoMath.distanceMeters(
          _last!.latitude, _last!.longitude, loc.latitude, loc.longitude);
    }
    _last = loc;
  }

  /// Compute progress: nearest un-visited stop as "next", plus distance/ETA.
  RouteProgress progress(
    GPSLocation loc, {
    double? speedMps,
    Set<String> visited = const {},
  }) {
    if (_stops.isEmpty) {
      return RouteProgress(
        routeId: _routeId,
        distanceTravelledMeters: _distanceTravelledMeters,
      );
    }

    final remaining =
        _stops.where((s) => !visited.contains(s.id)).toList(growable: false);
    if (remaining.isEmpty) {
      return RouteProgress(
        routeId: _routeId,
        distanceTravelledMeters: _distanceTravelledMeters,
        fractionComplete: 1,
      );
    }

    remaining.sort((a, b) {
      final da = GeoMath.distanceMeters(
          loc.latitude, loc.longitude, a.latitude, a.longitude);
      final db = GeoMath.distanceMeters(
          loc.latitude, loc.longitude, b.latitude, b.longitude);
      return da.compareTo(db);
    });

    final next = remaining.first;
    final distance = GeoMath.distanceMeters(
        loc.latitude, loc.longitude, next.latitude, next.longitude);

    return RouteProgress(
      routeId: _routeId,
      distanceTravelledMeters: _distanceTravelledMeters,
      nextStopId: next.id,
      distanceToNextMeters: distance,
      etaToNext: (speedMps != null && speedMps > 0)
          ? Duration(seconds: (distance / speedMps).round())
          : null,
      fractionComplete: (_stops.length - remaining.length) / _stops.length,
    );
  }
}
