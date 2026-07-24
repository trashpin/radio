import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_snapshot.dart';

/// Persists and reads USER location history as [TravelSnapshot]s.
///
/// WHY THIS EXISTS: to give the engine durable trip history and cross-device
/// continuity. It extends the generic [SupabaseSyncRepository], so recording a
/// snapshot (`upsert`) and reading history (`getAll`) reuse the shared
/// query/cache/sync plumbing — no duplicated data-access code. Location history
/// is user-owned data (writable), unlike read-only destination content.
///
/// NOTE: destination/park CONTENT is read via the existing `DestinationRepository`
/// and `ParkRepository` in the destinations feature (reused, not duplicated);
/// this GPS-specific repository covers location history only.
class LocationRepository extends SupabaseSyncRepository<TravelSnapshot> {
  LocationRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.locationHistory,
          fromJson: TravelSnapshot.fromJson,
          toJson: (snapshot) => snapshot.toJson(),
        );

  /// Records a snapshot to history.
  Future<void> record(TravelSnapshot snapshot) => upsert(snapshot);
}

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
