import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/radio/models/played_segment.dart';

/// Persists/reads listening history ([PlayedSegment] rows).
///
/// USER-OWNED data, so it extends the generic [SupabaseSyncRepository] (record +
/// read history). This is the durable backend behind the in-memory
/// `HistoryManager`; the two reconcile when auth/sync is wired.
class PlaybackRepository extends SupabaseSyncRepository<PlayedSegment> {
  PlaybackRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.playbackHistory,
          fromJson: PlayedSegment.fromJson,
          toJson: (played) => played.toJson(),
        );

  Future<void> record(PlayedSegment played) => upsert(played);
}

final playbackRepositoryProvider = Provider<PlaybackRepository>((ref) {
  return PlaybackRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
