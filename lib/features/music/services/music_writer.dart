import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// Write seam for bulk import (insert/upsert rows into the music tables).
///
/// WHY THIS EXISTS: the content tables are read-only for the *app*, but the
/// import tools must WRITE. Abstracting the writes lets [BulkImportService] be
/// unit-tested with a fake writer (no network) while production uses
/// [SupabaseMusicWriter]. Requires write access (authenticated/admin) at runtime.
abstract class MusicWriter {
  Future<void> upsertSongs(List<Json> rows);
  Future<void> upsertMetadata(List<Json> rows);
  Future<void> upsertAlbums(List<Json> rows);
}

class SupabaseMusicWriter implements MusicWriter {
  const SupabaseMusicWriter(this._client);
  final SupabaseClient _client;

  @override
  Future<void> upsertSongs(List<Json> rows) => _upsert(SupabaseTables.songs, rows);
  @override
  Future<void> upsertMetadata(List<Json> rows) =>
      _upsert(SupabaseTables.musicMetadata, rows);
  @override
  Future<void> upsertAlbums(List<Json> rows) =>
      _upsert(SupabaseTables.albums, rows);

  Future<void> _upsert(String table, List<Json> rows) async {
    if (rows.isEmpty) return;
    await _client.from(table).upsert(rows);
  }
}

final musicWriterProvider = Provider<MusicWriter>((ref) {
  return SupabaseMusicWriter(ref.watch(supabaseClientProvider));
});
