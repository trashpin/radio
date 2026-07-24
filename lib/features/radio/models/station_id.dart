import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';

/// A station identification jingle/voice tag ("You're listening to Explorer
/// Radio").
///
/// Read-only backend content produced by the StationIdentificationService on the
/// station's cadence. [toSegment] normalizes it at the station-ID priority tier.
class StationID implements Model {
  const StationID({
    required this.id,
    required this.stationId,
    required this.title,
    this.audioUrl,
    this.durationSeconds,
  });

  @override
  final String id;
  final String stationId;
  final String title;
  final String? audioUrl;
  final int? durationSeconds;

  factory StationID.fromJson(Json json) => StationID(
        id: json['id']?.toString() ?? '',
        stationId: json['station_id']?.toString() ?? '',
        title: (json['title'] ?? '') as String,
        audioUrl: json['audio_url'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      );

  AudioSegment toSegment() => AudioSegment(
        id: 'station_id:$id',
        title: title,
        type: AudioSegmentType.stationIdentification,
        priority: PlaybackPriority.stationIdentification,
        duration: Duration(seconds: durationSeconds ?? 0),
        audioUrl: audioUrl,
        stationId: stationId,
        interruptible: false,
        resumeAfter: true,
      );
}
