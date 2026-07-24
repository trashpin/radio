import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/gps/models/county_boundary.dart';

/// Read repository for [CountyBoundary] geometry used by the
/// CountyDetectionService.
class CountyBoundaryRepository extends SupabaseReadRepository<CountyBoundary> {
  CountyBoundaryRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.countyBoundaries,
          fromJson: CountyBoundary.fromJson,
        );

  Future<List<CountyBoundary>> byState(String stateCode) =>
      getWhere('state_code', stateCode);
}

final countyBoundaryRepositoryProvider =
    Provider<CountyBoundaryRepository>((ref) {
  return CountyBoundaryRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
