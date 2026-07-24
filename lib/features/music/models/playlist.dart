import 'package:explorer_os_mobile/core/data/model.dart';

/// A curated, ordered list of song ids.
///
/// USER-OWNED (provides [toJson]) so listeners can create/edit playlists.
/// `songIds` is stored denormalized (a `text[]`) for simple ordered retrieval;
/// the [PlaylistService] resolves ids → `Song`s via the song repository.
class Playlist implements Model {
  const Playlist({
    required this.id,
    required this.name,
    this.description,
    this.songIds = const [],
  });

  @override
  final String id;
  final String name;
  final String? description;
  final List<String> songIds;

  factory Playlist.fromJson(Json json) => Playlist(
        id: json['id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        description: json['description'] as String?,
        songIds: (json['song_ids'] as List?)?.cast<String>() ?? const [],
      );

  Json toJson() => {
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'song_ids': songIds,
      };
}
