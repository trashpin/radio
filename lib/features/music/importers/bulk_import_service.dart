import 'dart:typed_data';

import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/music/importers/csv_importer.dart';
import 'package:explorer_os_mobile/features/music/importers/zip_importer.dart';
import 'package:explorer_os_mobile/features/music/models/upload_job.dart';
import 'package:explorer_os_mobile/features/music/services/music_storage_service.dart';
import 'package:explorer_os_mobile/features/music/services/music_writer.dart';

/// Orchestrates bulk imports of thousands of songs from CSV or ZIP.
///
/// WHY THIS EXISTS: importing is a multi-step pipeline (parse → optionally
/// upload audio → persist rows → track progress) that shouldn't live in a UI or
/// repository. It composes [CSVImporter]/[ZIPImporter], the [MusicStorageService]
/// (audio bytes → Storage URL), and a [MusicWriter] (rows → DB), returning an
/// [UploadJob] describing the result. Fully testable with a fake writer.
class BulkImportService {
  BulkImportService({
    required this.writer,
    this.csvImporter = const CSVImporter(),
    this.zipImporter = const ZIPImporter(),
    this.storage,
  });

  final MusicWriter writer;
  final CSVImporter csvImporter;
  final ZIPImporter zipImporter;
  final MusicStorageService? storage;

  int _seq = 0;

  /// Imports songs described by a CSV string.
  Future<UploadJob> importCsv(String content) async {
    final rows = csvImporter.parse(content);
    final songRows = <Json>[];
    final metadataRows = <Json>[];

    for (final row in rows) {
      final songId = 'song_${_slug(row.title)}_${songRows.length}';
      songRows.add({
        'id': songId,
        'title': row.title,
        'artist': row.artist,
        'audio_url': row.audioUrl,
        'duration_seconds': row.durationSeconds,
        'station_id': row.stationId,
      });
      // Preserve album/genre/mood as metadata tags until they're resolved to ids
      // (a follow-up / AI-tagging step).
      final tags = [row.album, row.genre, row.mood]
          .whereType<String>()
          .toList(growable: false);
      if (tags.isNotEmpty) {
        metadataRows.add({
          'id': 'meta_$songId',
          'song_id': songId,
          'tags': tags,
        });
      }
    }

    await writer.upsertSongs(songRows);
    if (metadataRows.isNotEmpty) await writer.upsertMetadata(metadataRows);

    return UploadJob(
      id: 'job_${_seq++}',
      type: UploadJobType.csv,
      status: UploadJobStatus.completed,
      totalItems: rows.length,
      processedItems: rows.length,
      createdAt: DateTime.now(),
    );
  }

  /// Imports audio files from a ZIP: uploads each to Storage (when available)
  /// and persists a song row per track.
  Future<UploadJob> importZip(Uint8List zipBytes, {String? stationId}) async {
    final entries = zipImporter.extractAudio(zipBytes);
    final songRows = <Json>[];

    for (final entry in entries) {
      String? url;
      if (storage != null) {
        url = await storage!.uploadAudio('imports/${entry.name}', entry.bytes);
      }
      final songId = 'song_${_slug(entry.name)}_${songRows.length}';
      songRows.add({
        'id': songId,
        'title': _titleFromFilename(entry.name),
        'audio_url': url,
        'station_id': stationId,
      });
    }

    await writer.upsertSongs(songRows);

    return UploadJob(
      id: 'job_${_seq++}',
      type: UploadJobType.zip,
      status: UploadJobStatus.completed,
      totalItems: entries.length,
      processedItems: entries.length,
      createdAt: DateTime.now(),
    );
  }

  String _slug(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  String _titleFromFilename(String name) {
    final base = name.split('/').last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}
