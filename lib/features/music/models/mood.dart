import 'package:explorer_os_mobile/core/data/model.dart';

/// A mood tag (e.g. Calm, Energetic) used for context-aware selection (time of
/// day, daypart) and future AI tagging.
class Mood implements Model {
  const Mood({required this.id, required this.name, this.description});

  @override
  final String id;
  final String name;
  final String? description;

  factory Mood.fromJson(Json json) => Mood(
        id: json['id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        description: json['description'] as String?,
      );
}
