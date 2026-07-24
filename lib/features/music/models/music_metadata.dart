import 'package:explorer_os_mobile/core/data/model.dart';

/// Rich, per-song metadata linking a track to its album/genre/mood/artwork.
///
/// Kept separate from the core `Song` so metadata can be enriched (including by
/// future AI tagging) without touching the playable track record. Keyed by
/// [songId].
class MusicMetadata implements Model {
  const MusicMetadata({
    required this.id,
    required this.songId,
    this.albumId,
    this.genreId,
    this.moodId,
    this.artworkId,
    this.bpm,
    this.year,
    this.explicit = false,
    this.tags = const [],
    this.aiTagged = false,
  });

  @override
  final String id;
  final String songId;
  final String? albumId;
  final String? genreId;
  final String? moodId;
  final String? artworkId;
  final int? bpm;
  final int? year;
  final bool explicit;
  final List<String> tags;

  /// Whether tags were produced by the (future) AI tagging pipeline.
  final bool aiTagged;

  factory MusicMetadata.fromJson(Json json) => MusicMetadata(
        id: json['id']?.toString() ?? '',
        songId: json['song_id']?.toString() ?? '',
        albumId: json['album_id']?.toString(),
        genreId: json['genre_id']?.toString(),
        moodId: json['mood_id']?.toString(),
        artworkId: json['artwork_id']?.toString(),
        bpm: (json['bpm'] as num?)?.toInt(),
        year: (json['year'] as num?)?.toInt(),
        explicit: (json['explicit'] ?? false) as bool,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        aiTagged: (json['ai_tagged'] ?? false) as bool,
      );

  Json toJson() => {
        'id': id,
        'song_id': songId,
        if (albumId != null) 'album_id': albumId,
        if (genreId != null) 'genre_id': genreId,
        if (moodId != null) 'mood_id': moodId,
        if (artworkId != null) 'artwork_id': artworkId,
        if (bpm != null) 'bpm': bpm,
        if (year != null) 'year': year,
        'explicit': explicit,
        'tags': tags,
        'ai_tagged': aiTagged,
      };
}
