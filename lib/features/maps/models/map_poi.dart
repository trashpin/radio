import 'package:explorer_os_mobile/core/data/model.dart';

/// An editable Point of Interest for the admin Map Editor (row in
/// `map_locations`).
class MapPoi implements Model {
  const MapPoi({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.subcategory,
    this.description,
    this.imageUrl,
    this.audioUrl,
    this.triggerRadiusM,
    this.parkCode,
    this.destinationId,
  });

  @override
  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final String? subcategory;
  final String? description;
  final String? imageUrl;
  final String? audioUrl;
  final int? triggerRadiusM;
  final String? parkCode;
  final String? destinationId;

  MapPoi copyWith({
    String? name,
    String? category,
    double? latitude,
    double? longitude,
    String? description,
    int? triggerRadiusM,
  }) =>
      MapPoi(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        subcategory: subcategory,
        description: description ?? this.description,
        imageUrl: imageUrl,
        audioUrl: audioUrl,
        triggerRadiusM: triggerRadiusM ?? this.triggerRadiusM,
        parkCode: parkCode,
        destinationId: destinationId,
      );

  factory MapPoi.fromJson(Json j) => MapPoi(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Unnamed') as String,
        category: (j['category'] ?? 'poi') as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        subcategory: j['subcategory'] as String?,
        description: j['description'] as String?,
        imageUrl: j['image_url'] as String?,
        audioUrl: j['audio_url'] as String?,
        triggerRadiusM: (j['trigger_radius_m'] as num?)?.toInt(),
        parkCode: j['park_code']?.toString(),
        destinationId: j['destination_id']?.toString(),
      );

  Json toJson() => {
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'category': category,
        'latitude': latitude,
        'longitude': longitude,
        if (subcategory != null) 'subcategory': subcategory,
        if (description != null) 'description': description,
        if (imageUrl != null) 'image_url': imageUrl,
        if (audioUrl != null) 'audio_url': audioUrl,
        if (triggerRadiusM != null) 'trigger_radius_m': triggerRadiusM,
        if (parkCode != null) 'park_code': parkCode,
        if (destinationId != null) 'destination_id': destinationId,
      };
}
