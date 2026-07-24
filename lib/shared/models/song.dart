import 'package:explorer_os_mobile/core/data/model.dart';

/// A song belonging to a [RadioStation] playlist.
///
/// Read-only backend content. `stationId` links a song to its station;
/// `audioUrl` is the playable source and `durationSeconds` drives the player UI.
class Song implements Model {
  const Song({
    required this.id,
    required this.stationId,
    required this.title,
    this.artist,
    this.audioUrl,
    this.durationSeconds,
  });

  @override
  final String id;
  final String stationId;
  final String title;
  final String? artist;
  final String? audioUrl;
  final int? durationSeconds;

  factory Song.fromJson(Json json) => Song(
        id: json['id']?.toString() ?? '',
        stationId: json['station_id']?.toString() ?? '',
        title: (json['title'] ?? '') as String,
        artist: json['artist'] as String?,
        audioUrl: json['audio_url'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      );
}
