import 'package:explorer_os_mobile/features/gps/models/attraction_point.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/nearby_destination.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Finds attractions NEAR a position, nearest first.
///
/// WHY THIS EXISTS: proximity search is a focused, reusable concern (also useful
/// to the Explorer/Map screens independently of tracking). It's a pure function
/// over a candidate list, so it's trivially testable and has no state.
class NearbySearchService {
  const NearbySearchService();

  List<NearbyDestination> search(
    List<AttractionPoint> candidates,
    GPSLocation loc, {
    double radiusMeters = 5000,
    int limit = 10,
  }) {
    final results = <NearbyDestination>[];
    for (final c in candidates) {
      final distance = GeoMath.distanceMeters(
          loc.latitude, loc.longitude, c.latitude, c.longitude);
      if (distance > radiusMeters) continue;
      results.add(NearbyDestination(
        id: c.id,
        name: c.name,
        latitude: c.latitude,
        longitude: c.longitude,
        distanceMeters: distance,
        bearingDegrees: GeoMath.bearingDegrees(
            loc.latitude, loc.longitude, c.latitude, c.longitude),
        parkId: c.parkId,
      ));
    }
    results.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return results.take(limit).toList(growable: false);
  }
}
