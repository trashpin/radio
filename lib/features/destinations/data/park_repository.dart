import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/park.dart';

/// Read repository for [Park] content. Adds the destination relationship query;
/// all other behavior is inherited from [SupabaseReadRepository].
class ParkRepository extends SupabaseReadRepository<Park> {
  ParkRepository({
    required super.client,
    super.connectivity,
  }) : super(table: SupabaseTables.parks, fromJson: Park.fromJson);

  /// Parks belonging to a destination.
  Future<List<Park>> byDestination(String destinationId) =>
      getWhere('destination_id', destinationId);
}

final parkRepositoryProvider = Provider<ParkRepository>((ref) {
  return ParkRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// All parks.
final parksProvider = FutureProvider<List<Park>>(
  (ref) => ref.watch(parkRepositoryProvider).getAll(),
);

/// Parks for a given destination id.
final parksByDestinationProvider =
    FutureProvider.family<List<Park>, String>((ref, destinationId) {
  return ref.watch(parkRepositoryProvider).byDestination(destinationId);
});
