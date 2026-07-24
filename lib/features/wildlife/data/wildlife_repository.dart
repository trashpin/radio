import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/wildlife.dart';

/// Read repository for [Wildlife] content. Adds the park relationship query.
class WildlifeRepository extends SupabaseReadRepository<Wildlife> {
  WildlifeRepository({
    required super.client,
    super.connectivity,
  }) : super(table: SupabaseTables.wildlife, fromJson: Wildlife.fromJson);

  Future<List<Wildlife>> byPark(String parkId) => getWhere('park_id', parkId);
}

final wildlifeRepositoryProvider = Provider<WildlifeRepository>((ref) {
  return WildlifeRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// Wildlife for a given park id.
final wildlifeByParkProvider =
    FutureProvider.family<List<Wildlife>, String>((ref, parkId) {
  return ref.watch(wildlifeRepositoryProvider).byPark(parkId);
});
