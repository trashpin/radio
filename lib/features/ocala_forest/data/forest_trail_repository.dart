import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';

/// Read repository for [ForestTrail] — the exact same shape as
/// `ForestBoundaryRepository`/`ForestLocationRepository`, pointed at the
/// `forest_trails_with_geojson` VIEW (migration 0050) rather than the base
/// `forest_trails` table, since real PostGIS `geometry` columns aren't
/// directly representable to the Supabase-Flutter client — the view adds a
/// plain-text `geom_geojson` column PostgREST returns like any other field.
class ForestTrailRepository extends SupabaseReadRepository<ForestTrail> {
  ForestTrailRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.forestTrailsWithGeojson,
          fromJson: ForestTrail.fromJson,
        );
}

final forestTrailRepositoryProvider = Provider<ForestTrailRepository>((ref) {
  return ForestTrailRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
