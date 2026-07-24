import 'dart:math' as math;

/// Pure geospatial math shared by every GPS service.
///
/// Centralizing these formulas (great-circle distance, initial bearing) means
/// distance/heading logic is defined once and unit-tested independently of the
/// engine. No external packages — just `dart:math`.
class GeoMath {
  const GeoMath._();

  static const double earthRadiusMeters = 6371000;

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;
  static double _toDegrees(double radians) => radians * 180.0 / math.pi;

  /// Great-circle (haversine) distance in meters between two lat/lng points.
  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Initial bearing (0–360°, 0 = north) from point 1 to point 2.
  static double bearingDegrees(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final phi1 = _toRadians(lat1);
    final phi2 = _toRadians(lat2);
    final dLambda = _toRadians(lng2 - lng1);
    final y = math.sin(dLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
    final theta = math.atan2(y, x);
    return (_toDegrees(theta) + 360) % 360;
  }

  /// Absolute smallest angle (0–180°) between two bearings — used to decide if a
  /// destination lies "ahead" of the current heading.
  static double angularDifference(double a, double b) {
    final diff = ((a - b) % 360 + 360) % 360;
    return diff > 180 ? 360 - diff : diff;
  }
}
