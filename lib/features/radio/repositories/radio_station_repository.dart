import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

/// Read repository for [RadioStation] content. Built on the generic base.
class RadioStationRepository extends SupabaseReadRepository<RadioStation> {
  RadioStationRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.radioStations,
          fromJson: RadioStation.fromJson,
        );

  Future<List<RadioStation>> byDestination(String destinationId) =>
      getWhere('destination_id', destinationId);
}

final radioStationRepositoryProvider = Provider<RadioStationRepository>((ref) {
  return RadioStationRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// All radio stations.
final radioStationsProvider = FutureProvider<List<RadioStation>>(
  (ref) => ref.watch(radioStationRepositoryProvider).getAll(),
);
