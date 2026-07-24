import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/music/importers/bulk_import_service.dart';
import 'package:explorer_os_mobile/features/music/models/album.dart';
import 'package:explorer_os_mobile/features/music/models/upload_job.dart';
import 'package:explorer_os_mobile/features/music/repositories/music_repository.dart';
import 'package:explorer_os_mobile/features/music/services/music_storage_service.dart';
import 'package:explorer_os_mobile/features/music/services/music_writer.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

/// The app-facing entry point to the music library.
///
/// WHY THIS EXISTS: a single high-level surface for browsing (songs/albums/
/// search), building station playlists, and running bulk imports — composing
/// the [MusicRepository] (queries) and [BulkImportService] (writes). The Radio
/// Engine loads a station's playlist from here (via [songsForStation]) rather
/// than touching files.
class MusicLibraryService {
  const MusicLibraryService({required this.music, required this.importer});

  final MusicRepository music;
  final BulkImportService importer;

  Future<List<Song>> allSongs() => music.allSongs();
  Future<List<Album>> allAlbums() => music.allAlbums();
  Future<List<Song>> songsForStation(String stationId) =>
      music.songsForStation(stationId);

  /// Case-insensitive search over title/artist.
  Future<List<Song>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final all = await music.allSongs();
    return all
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            (s.artist?.toLowerCase().contains(q) ?? false))
        .toList(growable: false);
  }

  Future<UploadJob> importCsv(String content) => importer.importCsv(content);
  Future<UploadJob> importZip(Uint8List zipBytes, {String? stationId}) =>
      importer.importZip(zipBytes, stationId: stationId);
}

final bulkImportServiceProvider = Provider<BulkImportService>((ref) {
  return BulkImportService(
    writer: ref.watch(musicWriterProvider),
    storage: ref.watch(musicStorageServiceProvider),
  );
});

final musicLibraryServiceProvider = Provider<MusicLibraryService>((ref) {
  return MusicLibraryService(
    music: ref.watch(musicRepositoryProvider),
    importer: ref.watch(bulkImportServiceProvider),
  );
});
