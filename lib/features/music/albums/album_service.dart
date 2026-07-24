import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/music/models/album.dart';
import 'package:explorer_os_mobile/features/music/repositories/album_repository.dart';
import 'package:explorer_os_mobile/features/music/repositories/music_metadata_repository.dart';
import 'package:explorer_os_mobile/features/radio/repositories/song_repository.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

/// Album-level operations: list albums and resolve an album's tracks (via
/// per-song [MusicMetadata].albumId → songs).
class AlbumService {
  const AlbumService(this._albums, this._metadata, this._songs);

  final AlbumRepository _albums;
  final MusicMetadataRepository _metadata;
  final SongRepository _songs;

  Future<List<Album>> all() => _albums.getAll();
  Future<Album?> byId(String id) => _albums.getById(id);

  Future<List<Song>> songsForAlbum(String albumId) async {
    final metadata = await _metadata.byAlbum(albumId);
    final songIds = metadata.map((m) => m.songId).toSet();
    final all = await _songs.getAll();
    return all.where((s) => songIds.contains(s.id)).toList(growable: false);
  }
}

final albumServiceProvider = Provider<AlbumService>((ref) {
  return AlbumService(
    ref.watch(albumRepositoryProvider),
    ref.watch(musicMetadataRepositoryProvider),
    ref.watch(songRepositoryProvider),
  );
});
