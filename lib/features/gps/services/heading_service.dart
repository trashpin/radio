import 'package:explorer_os_mobile/features/gps/models/gps_heading.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Determines the direction of travel.
///
/// WHY THIS EXISTS: heading is needed both for the TravelContext and to decide
/// which attractions are "ahead". This service prefers a device-reported
/// heading when present, otherwise derives the bearing between two consecutive
/// fixes — keeping that fallback logic in one place.
class HeadingService {
  const HeadingService();

  /// Bearing (0–360°) from [from] to [to].
  double bearingBetween(GPSLocation from, GPSLocation to) =>
      GeoMath.bearingDegrees(
        from.latitude,
        from.longitude,
        to.latitude,
        to.longitude,
      );

  /// Resolves a [GPSHeading] for a new fix, using the device heading when
  /// available or the bearing from the [previous] fix.
  GPSHeading? resolve(GPSLocation current, {GPSLocation? previous}) {
    if (current.headingDegrees != null) {
      return GPSHeading.fromDegrees(current.headingDegrees!);
    }
    if (previous != null) {
      return GPSHeading.fromDegrees(bearingBetween(previous, current));
    }
    return null;
  }
}
