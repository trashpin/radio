import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';

/// A sponsor/commercial break segment (read-only backend content).
///
/// Scheduled, non-interruptible, resumes music after. Kept as its own type so
/// listeners can mute commercials via [RadioPreferences] / [AudioCategory].
class CommercialBreak implements Model {
  const CommercialBreak({
    required this.id,
    required this.title,
    this.sponsor,
    this.audioUrl,
    this.durationSeconds,
  });

  @override
  final String id;
  final String title;
  final String? sponsor;
  final String? audioUrl;
  final int? durationSeconds;

  factory CommercialBreak.fromJson(Json json) => CommercialBreak(
        id: json['id']?.toString() ?? '',
        title: (json['title'] ?? 'Sponsor') as String,
        sponsor: json['sponsor'] as String?,
        audioUrl: json['audio_url'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      );

  AudioSegment toSegment() => AudioSegment(
        id: 'commercial:$id',
        title: title,
        type: AudioSegmentType.commercial,
        priority: PlaybackPriority.scheduledAnnouncement,
        duration: Duration(seconds: durationSeconds ?? 0),
        audioUrl: audioUrl,
        tags: const ['commercial'],
        interruptible: false,
        resumeAfter: true,
      );
}
