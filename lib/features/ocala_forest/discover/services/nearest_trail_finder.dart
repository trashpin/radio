import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';

/// "The discovery automatically records the trail... when that information
/// is available" (spec §13) — a simple, pure nearest-vertex search over the
/// SAME real trail geometry v3 already imported, using the SAME
/// [GeoMath.distanceMeters] every other GPS feature in this app already
/// uses. Not a new trail/GPS system: no geofence, no trigger engine, just
/// "which trail's line passes closest to here right now."
///
/// An approximate trail position, exactly as the spec allows ("Approximate
/// trail position") — nearest-vertex rather than true point-to-segment
/// distance, which is more than precise enough given how densely USFS
/// trail geometry is vertexed.
String? nearestTrailId(
  double lat,
  double lng,
  List<ForestTrail> trails, {
  double maxMeters = 100,
}) {
  String? bestId;
  double bestDistance = double.infinity;
  for (final trail in trails) {
    for (final part in trail.parts) {
      for (final p in part) {
        final d = GeoMath.distanceMeters(lat, lng, p.lat, p.lng);
        if (d < bestDistance) {
          bestDistance = d;
          bestId = trail.id;
        }
      }
    }
  }
  if (bestId == null || bestDistance > maxMeters) return null;
  return bestId;
}
