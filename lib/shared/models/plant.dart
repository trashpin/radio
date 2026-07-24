import 'package:explorer_os_mobile/core/data/model.dart';

/// A plant/flora species found at a [Park].
///
/// Read-only backend content for the flora side of the nature guide. Mirrors
/// [Wildlife] in shape; kept as a distinct type for clear, type-safe queries.
class Plant implements Model {
  const Plant({
    required this.id,
    required this.parkId,
    required this.name,
    this.scientificName,
    this.description,
    this.imageUrl,
  });

  @override
  final String id;
  final String parkId;
  final String name;
  final String? scientificName;
  final String? description;
  final String? imageUrl;

  factory Plant.fromJson(Json json) => Plant(
        id: json['id']?.toString() ?? '',
        parkId: json['park_id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        scientificName: json['scientific_name'] as String?,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
      );
}
