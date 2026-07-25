import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/sightings/models/explorer_sighting.dart';

/// Read + write repository for `explorer_sightings`.
///
/// Reads reuse the generic [SupabaseReadRepository] (cache + error handling).
/// Writes are custom because the table's PK is `sighting_id` (not `id`): create
/// lets the DB generate the id/timestamp; delete keys on `sighting_id`.
class SightingRepository extends SupabaseReadRepository<ExplorerSighting> {
  SightingRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.explorerSightings,
          fromJson: ExplorerSighting.fromJson,
        );

  /// Inserts a sighting (DB generates `sighting_id` + `created_at`) and returns
  /// the persisted row.
  Future<ExplorerSighting> create(ExplorerSighting sighting) async {
    final payload = Map<String, dynamic>.from(sighting.toJson())
      ..remove('sighting_id');
    final rows = await client.from(table).insert(payload).select();
    return ExplorerSighting.fromJson(rows.first);
  }

  Future<void> deleteSighting(String id) =>
      client.from(table).delete().eq('sighting_id', id);

  /// Newest sightings first (bypasses cache for freshness).
  Future<List<ExplorerSighting>> recent({int limit = 100}) async {
    final rows = await client
        .from(table)
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows
        .map((r) => ExplorerSighting.fromJson(r))
        .toList(growable: false);
  }

  Future<List<ExplorerSighting>> byDestination(String destinationId) =>
      getWhere('destination_id', destinationId);
}

final sightingRepositoryProvider = Provider<SightingRepository>((ref) {
  return SightingRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
