import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/gps/models/park_boundary.dart';

/// Read repository for [ParkBoundary] geometry used by the ParkDetector.
class ParkBoundaryRepository extends SupabaseReadRepository<ParkBoundary> {
  ParkBoundaryRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.parkBoundaries,
          fromJson: ParkBoundary.fromJson,
        );

  Future<List<ParkBoundary>> byDestination(String destinationId) =>
      getWhere('destination_id', destinationId);
}

final parkBoundaryRepositoryProvider =
    Provider<ParkBoundaryRepository>((ref) {
  return ParkBoundaryRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
