import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';

/// Read repository for [ForestLocation] — the same generic shape as
/// `LocationRepository`, pointed at the new, isolated `forest_locations`
/// table (never the shared `locations` table Marion County content lives in).
class ForestLocationRepository extends SupabaseReadRepository<ForestLocation> {
  ForestLocationRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.forestLocations,
          fromJson: ForestLocation.fromJson,
        );

  Future<List<ForestLocation>> byForest(String forestId) =>
      getWhere('forest_id', forestId);
}

final forestLocationRepositoryProvider = Provider<ForestLocationRepository>((ref) {
  return ForestLocationRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
