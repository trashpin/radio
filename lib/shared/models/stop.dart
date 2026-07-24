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
  });

  @override
  final String id;
  final String parkId;
  final String name;
  final String? description;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final int? orderIndex;

  factory Stop.fromJson(Json json) => Stop(
        id: json['id']?.toString() ?? '',
        parkId: json['park_id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        orderIndex: (json['order_index'] as num?)?.toInt(),
      );
}
