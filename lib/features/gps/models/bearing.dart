import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';

/// A bearing TO a target point (direction you'd travel to reach it), as a
/// 0–360° angle plus its compass point.
///
/// Distinct from [GPSHeading] (the user's current direction of travel):
/// [Bearing] answers "which way is that destination from me?". Produced by the
/// BearingService and used for "the overlook is to your north-east" cues.
class Bearing {
  const Bearing({required this.degrees, required this.direction});

  final double degrees;
  final CardinalDirection direction;

  factory Bearing.fromDegrees(double degrees) {
    final normalized = (degrees % 360 + 360) % 360;
    return Bearing(
      degrees: normalized,
      direction: CardinalDirection.fromBearing(normalized),
    );
  }
}
