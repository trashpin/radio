import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/music/models/playlist.dart';
import 'package:explorer_os_mobile/features/music/repositories/playlist_repository.dart';
import 'package:explorer_os_mobile/features/radio/repositories/song_repository.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

/// Create/read playlists and resolve their ordered tracks.
class PlaylistService {
  const PlaylistService(this._playlists, this._songs);

  final PlaylistRepository _playlists;
  final SongRepository _songs;

  Future<List<Playlist>> all() => _playlists.getAll();
  Future<Playlist?> byId(String id) => _playlists.getById(id);
  Future<void> save(Playlist playlist) => _playlists.upsert(playlist);

  /// Resolves a playlist's songs in its stored order.
  Future<List<Song>> songs(String playlistId) async {
    final playlist = await _playlists.getById(playlistId);
    if (playlist == null) return const [];
    final all = await _songs.getAll();
    final byId = {for (final s in all) s.id: s};
    return playlist.songIds
        .map((id) => byId[id])
        .whereType<Song>()
        .toList(growable: false);
  }
}

final playlistServiceProvider = Provider<PlaylistService>((ref) {
  return PlaylistService(
    ref.watch(playlistRepositoryProvider),
    ref.watch(songRepositoryProvider),
  );
});
