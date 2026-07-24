import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';

/// The direction of travel, as a bearing plus its compass point.
///
/// Produced by the HeadingService from either a device heading or the bearing
/// between two consecutive fixes. The [direction] makes it human-friendly
/// ("heading north-east") for logging/UI and for the Producer's context.
class GPSHeading {
  const GPSHeading({required this.degrees, required this.direction});

  final double degrees;
  final CardinalDirection direction;

  factory GPSHeading.fromDegrees(double degrees) {
    final normalized = (degrees % 360 + 360) % 360;
    return GPSHeading(
      degrees: normalized,
      direction: CardinalDirection.fromBearing(normalized),
    );
  }
}
