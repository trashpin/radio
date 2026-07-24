import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/music/models/upload_job.dart';

/// Repository for bulk-import [UploadJob]s (sync — progress is recorded as the
/// importer runs).
class UploadJobRepository extends SupabaseSyncRepository<UploadJob> {
  UploadJobRepository({required super.client, super.connectivity})
      : super(
          table: SupabaseTables.uploadJobs,
          fromJson: UploadJob.fromJson,
          toJson: (job) => job.toJson(),
        );
}

final uploadJobRepositoryProvider = Provider<UploadJobRepository>((ref) {
  return UploadJobRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
