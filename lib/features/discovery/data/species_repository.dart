import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';

/// Read + write repository for the master `species` catalog.
///
/// Reads reuse the generic [SupabaseReadRepository] (cache + error handling).
/// Writes (used by admin/import tooling) key on `species_id`.
class SpeciesRepository extends SupabaseReadRepository<Species> {
  SpeciesRepository({
    required super.client,
    super.connectivity,
  }) : super(table: SupabaseTables.species, fromJson: Species.fromJson);

  Future<List<Species>> byCategory(String category) async {
    final rows = await client
        .from(table)
        .select()
        .eq('category', category)
        .eq('published', true)
        .order('common_name');
    return rows.map((r) => Species.fromJson(r)).toList(growable: false);
  }

  Future<List<Species>> byDestination(String destinationId) =>
      getWhere('destination_id', destinationId);

  /// Global search across common/scientific name.
  Future<List<Species>> search(String query) async {
    final rows = await client
        .from(table)
        .select()
        .or('common_name.ilike.%$query%,scientific_name.ilike.%$query%')
        .limit(50);
    return rows.map((r) => Species.fromJson(r)).toList(growable: false);
  }

  /// Inserts a species (DB generates id/timestamps) — for admin/import tooling.
  Future<Species> create(Species species) async {
    final payload = Map<String, dynamic>.from(species.toJson())
      ..remove('species_id');
    final rows = await client.from(table).insert(payload).select();
    return Species.fromJson(rows.first);
  }
}

final speciesRepositoryProvider = Provider<SpeciesRepository>((ref) {
  return SpeciesRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// Species in a given category (e.g. 'plants', 'birds', 'mammals').
final speciesByCategoryProvider =
    FutureProvider.family<List<Species>, String>((ref, category) {
  return ref.watch(speciesRepositoryProvider).byCategory(category);
});

/// Species present in a given destination/park (Popular in This Park, etc.).
final speciesByDestinationProvider =
    FutureProvider.family<List<Species>, String>((ref, destinationId) {
  return ref.watch(speciesRepositoryProvider).byDestination(destinationId);
});
