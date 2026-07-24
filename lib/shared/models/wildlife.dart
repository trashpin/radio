import 'package:explorer_os_mobile/core/data/model.dart';

/// A wildlife species observed at a [Park].
///
/// Read-only backend content for the Wildlife guide. `parkId` links the species
/// to its park; `scientificName` and imagery are optional.
class Wildlife implements Model {
  const Wildlife({
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

  factory Wildlife.fromJson(Json json) => Wildlife(
        id: json['id']?.toString() ?? '',
        parkId: json['park_id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        scientificName: json['scientific_name'] as String?,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
      );
}
