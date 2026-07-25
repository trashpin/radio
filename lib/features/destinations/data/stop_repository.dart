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

  /// Stops within a destination (Base44 `destination_id`).
  Future<List<Stop>> byDestination(String destinationId) =>
      getWhere('destination_id', destinationId);

  /// Backwards-compatible alias — Base44 keys stops on `destination_id`.
  Future<List<Stop>> byPark(String destinationId) =>
      byDestination(destinationId);
}

final stopRepositoryProvider = Provider<StopRepository>((ref) {
  return StopRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// Stops for a given destination id.
final stopsByDestinationProvider =
    FutureProvider.family<List<Stop>, String>((ref, destinationId) {
  return ref.watch(stopRepositoryProvider).byDestination(destinationId);
});

/// Backwards-compatible alias (destinations are the app's "parks").
final stopsByParkProvider = stopsByDestinationProvider;
