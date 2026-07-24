import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/stop.dart';

/// Read repository for [Stop] content. Adds the park relationship query.
class StopRepository extends SupabaseReadRepository<Stop> {
  StopRepository({
    required super.client,
    super.connectivity,
  }) : super(table: SupabaseTables.stops, fromJson: Stop.fromJson);

  /// Stops within a park.
  Future<List<Stop>> byPark(String parkId) => getWhere('park_id', parkId);
}

final stopRepositoryProvider = Provider<StopRepository>((ref) {
  return StopRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// Stops for a given park id.
final stopsByParkProvider =
    FutureProvider.family<List<Stop>, String>((ref, parkId) {
  return ref.watch(stopRepositoryProvider).byPark(parkId);
});
