import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// The geographic extent of a park, used by the ParkDetector.
///
/// Read-only backend content ([Model] so the generic repository can load it).
/// Modeled as a center + radius (circular approximation) today; a polygon can
/// replace [contains] later without changing callers. [approachRadiusMeters]
/// defines the "approaching" zone outside the park.
class ParkBoundary implements Model {
  const ParkBoundary({
    required this.id,
    required this.parkId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.approachRadiusMeters,
  });

  @override
  final String id;
  final String parkId;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  /// Distance outside [radiusMeters] within which the user is "approaching".
  final double? approachRadiusMeters;

  double get effectiveApproachRadius =>
      approachRadiusMeters ?? radiusMeters * 3;

  double distanceTo(double lat, double lng) =>
      GeoMath.distanceMeters(latitude, longitude, lat, lng);

  bool contains(double lat, double lng) => distanceTo(lat, lng) <= radiusMeters;

  bool isApproaching(double lat, double lng) {
    final d = distanceTo(lat, lng);
    return d > radiusMeters && d <= effectiveApproachRadius;
  }

  factory ParkBoundary.fromJson(Json json) => ParkBoundary(
        id: json['id']?.toString() ?? '',
        parkId: json['park_id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        radiusMeters: (json['radius_meters'] as num?)?.toDouble() ?? 1000,
        approachRadiusMeters:
            (json['approach_radius_meters'] as num?)?.toDouble(),
      );
}
