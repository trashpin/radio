import 'package:explorer_os_mobile/core/data/model.dart';

/// A point of interest (trailhead, overlook, spring…) within a [Park].
///
/// Read-only backend content. `parkId` links a stop to its park; `latitude`/
/// `longitude` power the future Map/GPS features; `orderIndex` allows an
/// itinerary ordering.
class Stop implements Model {
  const Stop({
    required this.id,
    required this.parkId,
    required this.name,
    this.description,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.orderIndex,
    this.stopType,
    this.audioAvailable = false,
    this.triggerRadiusMeters,
  });

  @override
  final String id;

  /// Owning destination id. Named `parkId` for historical reasons; it holds the
  /// Base44 `destination_id`.
  final String parkId;
  final String name;
  final String? description;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final int? orderIndex;

  /// Base44 `stop_type` (trailhead, overlook, spring…).
  final String? stopType;

  /// Base44 `audio_available` — whether this stop has audio.
  final bool audioAvailable;

  /// Base44 `gps_trigger_radius_meters` — geofence radius for triggering.
  final int? triggerRadiusMeters;

  /// Maps the Base44 `stops` schema (`stop_id`, `destination_id`, `stop_name`,
  /// `hero_image`, `sort_order`, …). Legacy keys (`id`, `park_id`, `name`,
  /// `image_url`, `order_index`) are accepted as fallbacks.
  factory Stop.fromJson(Json json) => Stop(
        id: (json['stop_id'] ?? json['id'])?.toString() ?? '',
        parkId:
            (json['destination_id'] ?? json['park_id'])?.toString() ?? '',
        name: (json['stop_name'] ?? json['name'] ?? '') as String,
        description: (json['short_description'] ??
            json['full_description'] ??
            json['description']) as String?,
        imageUrl: (json['hero_image'] ?? json['image_url']) as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        orderIndex:
            ((json['sort_order'] ?? json['order_index']) as num?)?.toInt(),
        stopType: json['stop_type'] as String?,
        audioAvailable: (json['audio_available'] ?? false) as bool,
        triggerRadiusMeters:
            (json['gps_trigger_radius_meters'] as num?)?.toInt(),
      );
}
