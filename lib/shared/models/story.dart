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
    this.category,
    this.shortSummary,
    this.voiceScript,
    this.heroMediaId,
  });

  @override
  final String id;

  /// Owning destination id (Base44 `destination_id`); named `parkId` for
  /// historical reasons.
  final String parkId;
  final String title;
  final String? stopId;

  /// Long-form text (Base44 `full_story`, falling back to `short_summary`).
  final String? body;
  final String? imageUrl;

  /// Base44 `story_category`.
  final String? category;

  /// Base44 `short_summary`.
  final String? shortSummary;

  /// Base44 `voice_script` — the narration script.
  final String? voiceScript;

  /// Base44 `hero_media_id` → `media.media_id`.
  final String? heroMediaId;

  /// Maps the Base44 `stories` schema. Legacy keys (`id`, `park_id`, `body`,
  /// `image_url`) are accepted as fallbacks.
  factory Story.fromJson(Json json) => Story(
        id: (json['story_id'] ?? json['id'])?.toString() ?? '',
        parkId:
            (json['destination_id'] ?? json['park_id'])?.toString() ?? '',
        title: (json['title'] ?? '') as String,
        stopId: json['stop_id']?.toString(),
        body: (json['full_story'] ??
            json['short_summary'] ??
            json['body']) as String?,
        imageUrl: json['image_url'] as String?,
        category: json['story_category'] as String?,
        shortSummary: json['short_summary'] as String?,
        voiceScript: json['voice_script'] as String?,
        heroMediaId: json['hero_media_id']?.toString(),
      );
}
