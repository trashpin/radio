import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/gps/models/state_boundary.dart';

/// Read repository for state geometry ([StateBoundary]) used to detect the
/// current state. (This is the "StateRepository" of the GPS engine; destination
/// and park CONTENT are read from the destinations feature's repositories.)
class StateRepository extends SupabaseReadRepository<StateBoundary> {
  StateRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.stateBoundaries,
          fromJson: StateBoundary.fromJson,
        );
}

final stateRepositoryProvider = Provider<StateRepository>((ref) {
  return StateRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
