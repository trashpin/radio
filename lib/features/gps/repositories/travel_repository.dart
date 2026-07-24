import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_session.dart';

/// Persists and reads USER [TravelSession]s (trip summaries/history).
///
/// WHY THIS EXISTS: to durably record completed trips for a future "your trips"
/// experience and cross-device continuity. Extends the generic
/// [SupabaseSyncRepository], so save (`upsert`) and read (`getAll`) reuse the
/// shared query/cache/sync plumbing. Sessions are user-owned (writable).
///
/// NOTE: destination/park CONTENT is read via the existing `DestinationRepository`
/// and `ParkRepository` (features/destinations); state/county/park geometry via
/// the boundary repositories; and live fixes via `LocationRepository`. This
/// repository covers trip sessions only — no duplication.
class TravelRepository extends SupabaseSyncRepository<TravelSession> {
  TravelRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.travelSessions,
          fromJson: TravelSession.fromJson,
          toJson: (session) => session.toJson(),
        );

  Future<void> save(TravelSession session) => upsert(session);
}

final travelRepositoryProvider = Provider<TravelRepository>((ref) {
  return TravelRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
