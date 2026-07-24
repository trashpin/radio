import 'package:explorer_os_mobile/core/data/model.dart';

/// A music album grouping tracks in the library (read-only content for the app;
/// authored via the import tools).
class Album implements Model {
  const Album({
    required this.id,
    required this.title,
    this.artist,
    this.year,
    this.artworkId,
    this.description,
  });

  @override
  final String id;
  final String title;
  final String? artist;
  final int? year;
  final String? artworkId;
  final String? description;

  factory Album.fromJson(Json json) => Album(
        id: json['id']?.toString() ?? '',
        title: (json['title'] ?? '') as String,
        artist: json['artist'] as String?,
        year: (json['year'] as num?)?.toInt(),
        artworkId: json['artwork_id']?.toString(),
        description: json['description'] as String?,
      );
}
