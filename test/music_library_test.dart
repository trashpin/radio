// Tests for Music Management: CSV parsing, model mapping, and the bulk-import
// pipeline (via a fake MusicWriter — no network).

import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/music/importers/bulk_import_service.dart';
import 'package:explorer_os_mobile/features/music/importers/csv_importer.dart';
import 'package:explorer_os_mobile/features/music/models/music_metadata.dart';
import 'package:explorer_os_mobile/features/music/models/upload_job.dart';
import 'package:explorer_os_mobile/features/music/services/music_writer.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMusicWriter implements MusicWriter {
  final List<Json> songs = [];
  final List<Json> metadata = [];
  final List<Json> albums = [];

  @override
  Future<void> upsertSongs(List<Json> rows) async => songs.addAll(rows);
  @override
  Future<void> upsertMetadata(List<Json> rows) async => metadata.addAll(rows);
  @override
  Future<void> upsertAlbums(List<Json> rows) async => albums.addAll(rows);
}

const _csv = '''
title,artist,album,genre,mood,audio_url,duration_seconds,station_id
Trail Opener,ExplorerOS,Adventures,Variety,Upbeat,https://a/1.mp3,372,explorer_radio
Open Road,ExplorerOS,Adventures,Country,Easygoing,https://a/2.mp3,425,country_roads
,Missing Title,,,,,,
''';

void main() {
  test('CSVImporter parses rows and maps header columns', () {
    final rows = const CSVImporter().parse(_csv);
    expect(rows.length, 2); // the title-less row is skipped
    expect(rows.first.title, 'Trail Opener');
    expect(rows.first.artist, 'ExplorerOS');
    expect(rows.first.album, 'Adventures');
    expect(rows.first.durationSeconds, 372);
    expect(rows.first.stationId, 'explorer_radio');
    expect(rows[1].genre, 'Country');
  });

  test('BulkImportService.importCsv writes songs + metadata', () async {
    final writer = FakeMusicWriter();
    final service = BulkImportService(writer: writer);

    final job = await service.importCsv(_csv);

    expect(job.status, UploadJobStatus.completed);
    expect(job.totalItems, 2);
    expect(writer.songs.length, 2);
    expect(writer.songs.first['title'], 'Trail Opener');
    expect(writer.songs.first['audio_url'], 'https://a/1.mp3');
    // album/genre/mood preserved as metadata tags.
    expect(writer.metadata.length, 2);
    expect((writer.metadata.first['tags'] as List), contains('Adventures'));
  });

  test('MusicMetadata round-trips JSON', () {
    final meta = MusicMetadata.fromJson(const {
      'id': 'm1',
      'song_id': 's1',
      'album_id': 'a1',
      'genre_id': 'g1',
      'tags': ['road', 'sunny'],
      'ai_tagged': true,
    });
    expect(meta.songId, 's1');
    expect(meta.albumId, 'a1');
    expect(meta.aiTagged, isTrue);
    expect(meta.toJson()['song_id'], 's1');
    expect(meta.toJson()['tags'], ['road', 'sunny']);
  });
}
