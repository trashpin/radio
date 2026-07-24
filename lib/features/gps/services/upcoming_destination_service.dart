import 'package:explorer_os_mobile/features/gps/models/attraction_point.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/upcoming_destination.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Finds attractions AHEAD of the user (within a cone of the heading), nearest
/// first, with an ETA when a speed is known.
///
/// WHY THIS EXISTS: "what's coming up on my route?" is the signal the AI
/// Producer uses to pre-load location audio. Isolating it (from generic
/// proximity) keeps the directional logic focused and reusable. Pure/stateless.
class UpcomingDestinationService {
  const UpcomingDestinationService();

  List<UpcomingDestination> search(
    List<AttractionPoint> candidates,
    GPSLocation loc,
    double headingDegrees, {
    Set<String> visited = const {},
    double coneDegrees = 60,
    double radiusMeters = 20000,
    double? speedMps,
    int limit = 5,
  }) {
    final results = <UpcomingDestination>[];
    for (final c in candidates) {
      if (visited.contains(c.id)) continue;
      final distance = GeoMath.distanceMeters(
          loc.latitude, loc.longitude, c.latitude, c.longitude);
      if (distance > radiusMeters) continue;
      final bearing = GeoMath.bearingDegrees(
          loc.latitude, loc.longitude, c.latitude, c.longitude);
      if (GeoMath.angularDifference(headingDegrees, bearing) > coneDegrees) {
        continue;
      }
      results.add(UpcomingDestination(
        id: c.id,
        name: c.name,
        latitude: c.latitude,
        longitude: c.longitude,
        distanceMeters: distance,
        bearingDegrees: bearing,
        eta: (speedMps != null && speedMps > 0)
            ? Duration(seconds: (distance / speedMps).round())
            : null,
        parkId: c.parkId,
      ));
    }
    results.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return results.take(limit).toList(growable: false);
  }
}
