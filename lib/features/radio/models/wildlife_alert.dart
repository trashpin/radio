import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';

/// A wildlife sighting/story segment (e.g. "bison ahead on the right").
///
/// Read-only backend content. [toSegment] normalizes it for the queue at the
/// scheduled-announcement tier (interrupts music, resumes after).
class WildlifeAlert implements Model {
  const WildlifeAlert({
    required this.id,
    required this.title,
    this.species,
    this.message,
    this.audioUrl,
    this.durationSeconds,
    this.parkId,
  });

  @override
  final String id;
  final String title;
  final String? species;
  final String? message;
  final String? audioUrl;
  final int? durationSeconds;
  final String? parkId;

  factory WildlifeAlert.fromJson(Json json) => WildlifeAlert(
        id: json['id']?.toString() ?? '',
        title: (json['title'] ?? 'Wildlife') as String,
        species: json['species'] as String?,
        message: json['message'] as String?,
        audioUrl: json['audio_url'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        parkId: json['park_id']?.toString(),
      );

  AudioSegment toSegment() => AudioSegment(
        id: 'wildlife:$id',
        title: title,
        type: AudioSegmentType.wildlifeAlert,
        priority: PlaybackPriority.scheduledAnnouncement,
        duration: Duration(seconds: durationSeconds ?? 0),
        audioUrl: audioUrl,
        parkId: parkId,
        interruptible: false,
        resumeAfter: true,
      );
}
