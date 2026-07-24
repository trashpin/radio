import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/music/repositories/album_repository.dart';
import 'package:explorer_os_mobile/features/music/repositories/music_metadata_repository.dart';
import 'package:explorer_os_mobile/features/music/repositories/station_assignment_repository.dart';
import 'package:explorer_os_mobile/features/radio/repositories/song_repository.dart';
import 'package:explorer_os_mobile/features/music/models/album.dart';
import 'package:explorer_os_mobile/features/music/models/music_metadata.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

/// The central music-library data facade — the "Music Repository" the Radio
/// Engine queries instead of reading files.
///
/// WHY THIS EXISTS: the Radio Engine (via `StationManager`) needs songs for a
/// station; it should ask ONE place, not touch storage/files or juggle several
/// repositories. This facade composes the reused radio `SongRepository` with the
/// music `StationAssignmentRepository`/`AlbumRepository`/`MusicMetadataRepository`
/// and resolves a station's playlist from explicit assignments (falling back to
/// the song's own `stationId`). Audio bytes live in Supabase Storage; this only
/// deals in metadata rows + resolved `audioUrl`s.
class MusicRepository {
  const MusicRepository({
    required this.songs,
    required this.albums,
    required this.assignments,
    required this.metadata,
  });

  final SongRepository songs;
  final AlbumRepository albums;
  final StationAssignmentRepository assignments;
  final MusicMetadataRepository metadata;

  Future<List<Song>> allSongs() => songs.getAll();
  Future<List<Album>> allAlbums() => albums.getAll();
  Future<MusicMetadata?> metadataForSong(String songId) =>
      metadata.forSong(songId);

  /// Resolves the songs assigned to a station. Prefers explicit
  /// [StationAssignment]s (many-to-many); if none exist, falls back to songs
  /// whose own `stationId` matches.
  Future<List<Song>> songsForStation(String stationId) async {
    final stationAssignments = await assignments.forStation(stationId);
    if (stationAssignments.isEmpty) {
      return songs.byStation(stationId);
    }
    final assignedIds =
        stationAssignments.map((a) => a.songId).toSet();
    final all = await songs.getAll();
    return all.where((s) => assignedIds.contains(s.id)).toList(growable: false);
  }
}

final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  return MusicRepository(
    songs: ref.watch(songRepositoryProvider),
    albums: ref.watch(albumRepositoryProvider),
    assignments: ref.watch(stationAssignmentRepositoryProvider),
    metadata: ref.watch(musicMetadataRepositoryProvider),
  );
});
