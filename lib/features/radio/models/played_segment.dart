import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';

/// A persisted record of a segment that played (the row type for
/// `playback_history`).
///
/// USER-OWNED (provides [toJson]); the durable counterpart to the in-memory
/// [PlaybackHistory] snapshot. Written by the PlaybackRepository for a future
/// "recently played" / listening-history experience.
class PlayedSegment implements Model {
  const PlayedSegment({
    required this.id,
    required this.segmentId,
    required this.title,
    required this.type,
    required this.playedAt,
    this.stationId,
  });

  @override
  final String id;
  final String segmentId;
  final String title;
  final AudioSegmentType type;
  final DateTime playedAt;
  final String? stationId;

  factory PlayedSegment.fromSegment(AudioSegment segment, {String? stationId}) {
    final now = DateTime.now();
    return PlayedSegment(
      id: '${segment.id}@${now.millisecondsSinceEpoch}',
      segmentId: segment.id,
      title: segment.title,
      type: segment.type,
      playedAt: now,
      stationId: stationId ?? segment.stationId,
    );
  }

  factory PlayedSegment.fromJson(Json json) => PlayedSegment(
        id: json['id']?.toString() ?? '',
        segmentId: json['segment_id']?.toString() ?? '',
        title: (json['title'] ?? '') as String,
        type: AudioSegmentType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => AudioSegmentType.music,
        ),
        playedAt: DateTime.tryParse(json['played_at']?.toString() ?? '') ??
            DateTime.now(),
        stationId: json['station_id']?.toString(),
      );

  Json toJson() => {
        'id': id,
        'segment_id': segmentId,
        'title': title,
        'type': type.name,
        'played_at': playedAt.toIso8601String(),
        if (stationId != null) 'station_id': stationId,
      };
}
