import 'package:explorer_os_mobile/core/data/model.dart';

/// A read-only AI Ranger knowledge article from Base44's `knowledge_articles`.
///
/// Linked to a destination (and optionally a stop). Carries both display text
/// (`summary`/`content`) and a `voiceScript` for narration, plus an optional
/// `heroMediaId` → `media.media_id`.
class KnowledgeArticle implements Model {
  const KnowledgeArticle({
    required this.id,
    required this.destinationId,
    required this.title,
    this.stopId,
    this.category,
    this.summary,
    this.content,
    this.voiceScript,
    this.aiSummary,
    this.heroMediaId,
    this.readingTimeMinutes,
    this.audioLengthSeconds,
    this.featured = false,
    this.published = true,
    this.sortOrder,
  });

  @override
  final String id;
  final String destinationId;
  final String title;
  final String? stopId;
  final String? category;
  final String? summary;
  final String? content;
  final String? voiceScript;
  final String? aiSummary;
  final String? heroMediaId;
  final int? readingTimeMinutes;
  final int? audioLengthSeconds;
  final bool featured;
  final bool published;
  final int? sortOrder;

  factory KnowledgeArticle.fromJson(Json json) => KnowledgeArticle(
        id: (json['knowledge_id'] ?? json['id'])?.toString() ?? '',
        destinationId: json['destination_id']?.toString() ?? '',
        title: (json['title'] ?? '') as String,
        stopId: json['stop_id']?.toString(),
        category: json['category'] as String?,
        summary: json['summary'] as String?,
        content: json['content'] as String?,
        voiceScript: json['voice_script'] as String?,
        aiSummary: json['ai_summary'] as String?,
        heroMediaId: json['hero_media_id']?.toString(),
        readingTimeMinutes: (json['reading_time_minutes'] as num?)?.toInt(),
        audioLengthSeconds: (json['audio_length_seconds'] as num?)?.toInt(),
        featured: (json['featured'] ?? false) as bool,
        published: (json['published'] ?? true) as bool,
        sortOrder: (json['sort_order'] as num?)?.toInt(),
      );
}
