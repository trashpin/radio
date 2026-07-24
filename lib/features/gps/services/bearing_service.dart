import 'package:explorer_os_mobile/features/gps/models/bearing.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Computes the bearing TO a target point.
///
/// WHY THIS EXISTS: while HeadingService describes the direction the user is
/// travelling, BearingService answers "which way is X from me?" — used for
/// directional cues about destinations ("the falls are to your north"). Kept
/// separate for clarity; both delegate to [GeoMath] (no duplicated math).
class BearingService {
  const BearingService();

  Bearing to(GPSLocation from, double targetLat, double targetLng) {
    final degrees = GeoMath.bearingDegrees(
        from.latitude, from.longitude, targetLat, targetLng);
    return Bearing.fromDegrees(degrees);
  }

  Bearing between(GPSLocation from, GPSLocation to) =>
      Bearing.fromDegrees(GeoMath.bearingDegrees(
          from.latitude, from.longitude, to.latitude, to.longitude));
}
