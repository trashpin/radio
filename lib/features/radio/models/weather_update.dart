import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';

/// A spoken weather update segment (read-only backend content).
///
/// The AnnouncementScheduler/AI Producer decides WHEN it plays; [toSegment]
/// normalizes it into an [AudioSegment] the engine can queue/interrupt with.
class WeatherUpdate implements Model {
  const WeatherUpdate({
    required this.id,
    required this.title,
    this.audioUrl,
    this.durationSeconds,
    this.summary,
    this.location,
  });

  @override
  final String id;
  final String title;
  final String? audioUrl;
  final int? durationSeconds;
  final String? summary;
  final String? location;

  factory WeatherUpdate.fromJson(Json json) => WeatherUpdate(
        id: json['id']?.toString() ?? '',
        title: (json['title'] ?? 'Weather') as String,
        audioUrl: json['audio_url'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        summary: json['summary'] as String?,
        location: json['location'] as String?,
      );

  AudioSegment toSegment() => AudioSegment(
        id: 'weather:$id',
        title: title,
        type: AudioSegmentType.weather,
        priority: PlaybackPriority.scheduledAnnouncement,
        duration: Duration(seconds: durationSeconds ?? 0),
        audioUrl: audioUrl,
        interruptible: false,
        resumeAfter: true,
      );
}
