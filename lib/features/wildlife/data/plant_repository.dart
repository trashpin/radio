import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/plant.dart';

/// Read repository for [Plant] content. Adds the park relationship query.
class PlantRepository extends SupabaseReadRepository<Plant> {
  PlantRepository({
    required super.client,
    super.connectivity,
  }) : super(table: SupabaseTables.plants, fromJson: Plant.fromJson);

  Future<List<Plant>> byPark(String parkId) => getWhere('park_id', parkId);
}

final plantRepositoryProvider = Provider<PlantRepository>((ref) {
  return PlantRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// Plants for a given park id.
final plantsByParkProvider =
    FutureProvider.family<List<Plant>, String>((ref, parkId) {
  return ref.watch(plantRepositoryProvider).byPark(parkId);
});
