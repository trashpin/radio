import 'package:explorer_os_mobile/core/data/model.dart';

/// A narrated story tied to a [Park] and optionally a specific [Stop].
///
/// Read-only backend content that powers the Stories / AI Ranger experience.
/// The actual audio lives in [Narration] records linked by `storyId`.
class Story implements Model {
  const Story({
    required this.id,
    required this.parkId,
    required this.title,
    this.stopId,
    this.body,
    this.imageUrl,
  });

  @override
  final String id;
  final String parkId;
  final String title;
  final String? stopId;
  final String? body;
  final String? imageUrl;

  factory Story.fromJson(Json json) => Story(
        id: json['id']?.toString() ?? '',
        parkId: json['park_id']?.toString() ?? '',
        title: (json['title'] ?? '') as String,
        stopId: json['stop_id']?.toString(),
        body: json['body'] as String?,
        imageUrl: json['image_url'] as String?,
      );
}
