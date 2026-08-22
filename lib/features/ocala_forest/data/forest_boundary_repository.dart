import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_boundary.dart';

/// Read repository for [ForestBoundary] — the exact same shape as
/// `CountyBoundaryRepository`/`ParkBoundaryRepository`, pointed at the new,
/// isolated `forest_boundaries` table.
class ForestBoundaryRepository extends SupabaseReadRepository<ForestBoundary> {
  ForestBoundaryRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.forestBoundaries,
          fromJson: ForestBoundary.fromJson,
        );
}

final forestBoundaryRepositoryProvider = Provider<ForestBoundaryRepository>((ref) {
  return ForestBoundaryRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
