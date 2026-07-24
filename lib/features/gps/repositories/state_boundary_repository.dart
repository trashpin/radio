import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/gps/models/state_boundary.dart';

/// Read repository for [StateBoundary] bounding boxes used to detect the
/// current state.
class StateBoundaryRepository extends SupabaseReadRepository<StateBoundary> {
  StateBoundaryRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.stateBoundaries,
          fromJson: StateBoundary.fromJson,
        );
}

final stateBoundaryRepositoryProvider =
    Provider<StateBoundaryRepository>((ref) {
  return StateBoundaryRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
