import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/download.dart';

/// Repository for USER-OWNED offline downloads.
///
/// Extends [SupabaseSyncRepository] so download records can be persisted/synced
/// (create, update progress, delete) via inherited `upsert`/`deleteById`. When
/// the real download engine lands, it will report progress through this
/// repository, and offline playback will read [Download.localPath].
class DownloadRepository extends SupabaseSyncRepository<Download> {
  DownloadRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.downloads,
          fromJson: Download.fromJson,
          toJson: (download) => download.toJson(),
        );

  /// Downloads filtered by lifecycle status (e.g. only completed).
  Future<List<Download>> byStatus(DownloadStatus status) =>
      getWhere('status', status.name);
}

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  return DownloadRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// All download records.
final downloadsProvider = FutureProvider<List<Download>>(
  (ref) => ref.watch(downloadRepositoryProvider).getAll(),
);
