import 'package:explorer_os_mobile/core/data/model.dart';

/// A park within a [Destination] (e.g. "Ocala National Forest").
///
/// Read-only backend content. `destinationId` is the foreign key used to query
/// all parks for a destination. Optional fields degrade gracefully when absent.
class Park implements Model {
  const Park({
    required this.id,
    required this.destinationId,
    required this.name,
    this.description,
    this.imageUrl,
    this.location,
  });

  @override
  final String id;
  final String destinationId;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? location;

  factory Park.fromJson(Json json) => Park(
        id: json['id']?.toString() ?? '',
        destinationId: json['destination_id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        location: json['location'] as String?,
      );
}
