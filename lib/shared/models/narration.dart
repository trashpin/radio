import 'package:explorer_os_mobile/core/data/model.dart';

/// An audio narration for a [Story] (and optionally a specific [Stop]).
///
/// Read-only backend content. Separated from [Story] because a single story can
/// have multiple narrations (languages, chapters, voices). `audioUrl` is the
/// playable source; `transcript` supports accessibility/captions.
class Narration implements Model {
  const Narration({
    required this.id,
    required this.storyId,
    required this.title,
    this.stopId,
    this.audioUrl,
    this.durationSeconds,
    this.transcript,
  });

  @override
  final String id;
  final String storyId;
  final String title;
  final String? stopId;
  final String? audioUrl;
  final int? durationSeconds;
  final String? transcript;

  factory Narration.fromJson(Json json) => Narration(
        id: json['id']?.toString() ?? '',
        storyId: json['story_id']?.toString() ?? '',
        title: (json['title'] ?? '') as String,
        stopId: json['stop_id']?.toString(),
        audioUrl: json['audio_url'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        transcript: json['transcript'] as String?,
      );
}
