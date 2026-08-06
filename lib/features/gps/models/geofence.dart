import 'package:explorer_os_mobile/features/gps/models/geofence_level.dart';

/// One node in the geofence hierarchy — a circle (center + radius) at a
/// given [level], optionally nested under a [parentId] (another geofence's
/// id), pointing at a [locationId] in the existing `locations` table for
/// its content (name, images, narration — unchanged, nothing new there).
class Geofence {
  const Geofence({
    required this.id,
    required this.locationId,
    required this.level,
    this.parentId,
    required this.centerLat,
    required this.centerLng,
    required this.radiusMeters,
    this.priorityOverride,
    this.active = true,
  });

  final String id;
  final String locationId;
  final GeofenceLevel level;
  final String? parentId;
  final double centerLat;
  final double centerLng;
  final double radiusMeters;

  /// Overrides [GeofenceLevel.defaultPriority] for this specific geofence
  /// when set — used to break ties among several geofences at the same
  /// depth (e.g. two overlapping POIs).
  final int? priorityOverride;
  final bool active;

  int get effectivePriority => priorityOverride ?? level.defaultPriority;

  factory Geofence.fromJson(Map<String, dynamic> j) => Geofence(
        id: (j['id'] ?? '').toString(),
        locationId: (j['location_id'] ?? '').toString(),
        level: GeofenceLevel.fromId(j['level'] as String?) ?? GeofenceLevel.poi,
        parentId: j['parent_id'] as String?,
        centerLat: (j['center_lat'] as num).toDouble(),
        centerLng: (j['center_lng'] as num).toDouble(),
        radiusMeters: (j['radius_meters'] as num).toDouble(),
        priorityOverride: (j['priority_override'] as num?)?.toInt(),
        active: (j['active'] ?? true) as bool,
      );

  Map<String, dynamic> toWrite() => {
        'location_id': locationId,
        'level': level.id,
        'parent_id': parentId,
        'center_lat': centerLat,
        'center_lng': centerLng,
        'radius_meters': radiusMeters,
        'priority_override': priorityOverride,
        'active': active,
      };
}

/// A [Geofence] the traveler is currently inside, plus how far from its
/// center they are (0 = standing exactly on it).
class GeofenceMatch {
  const GeofenceMatch({required this.geofence, required this.distanceMeters});
  final Geofence geofence;
  final double distanceMeters;

  GeofenceLevel get level => geofence.level;
  int get effectivePriority => geofence.effectivePriority;
}
