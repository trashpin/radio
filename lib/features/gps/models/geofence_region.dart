import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// What a geofence represents (used for classifying enter/exit events).
enum GeofenceType { park, attraction, route, custom }

/// A circular geofence the GeofenceEngine watches for enter/exit transitions.
///
/// Circular (center + radius) for now; a polygon variant can be added later
/// without changing the engine's enter/exit contract. [contains] is the single
/// membership test used by the engine.
class GeofenceRegion {
  const GeofenceRegion({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.type = GeofenceType.custom,
    this.referenceId,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final GeofenceType type;

  /// Optional id of the entity this fence represents (e.g. a park or stop id).
  final String? referenceId;

  /// True when the given position lies inside the fence.
  bool contains(double lat, double lng) =>
      GeoMath.distanceMeters(latitude, longitude, lat, lng) <= radiusMeters;
}
