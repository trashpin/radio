import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Distance and ETA calculations, in one place.
///
/// WHY THIS EXISTS: several services and the public API need "how far?" and
/// "how long until arrival?". Wrapping [GeoMath] here gives a small, mockable
/// service with domain-friendly signatures (works directly with [GPSLocation]).
class DistanceService {
  const DistanceService();

  /// Great-circle distance in meters between two fixes.
  double between(GPSLocation a, GPSLocation b) =>
      GeoMath.distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude);

  /// Meters between raw coordinate pairs.
  double betweenCoords(double lat1, double lng1, double lat2, double lng2) =>
      GeoMath.distanceMeters(lat1, lng1, lat2, lng2);

  /// Estimated time of arrival given a distance and a speed. Null when the user
  /// isn't moving (speed <= 0) — an ETA would be meaningless.
  Duration? eta(double distanceMeters, double? speedMps) {
    if (speedMps == null || speedMps <= 0) return null;
    return Duration(seconds: (distanceMeters / speedMps).round());
  }
}
