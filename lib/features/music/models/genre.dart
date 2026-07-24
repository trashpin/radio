import 'package:explorer_os_mobile/core/data/model.dart';

/// A music genre (e.g. Country, Ambient). Used to classify tracks and to bias
/// station selection.
class Genre implements Model {
  const Genre({required this.id, required this.name, this.description});

  @override
  final String id;
  final String name;
  final String? description;

  factory Genre.fromJson(Json json) => Genre(
        id: json['id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        description: json['description'] as String?,
      );
}
