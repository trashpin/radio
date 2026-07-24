import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/radio/models/station_profile.dart';

/// Read repository for [StationProfile] editorial content.
class StationProfileRepository extends SupabaseReadRepository<StationProfile> {
  StationProfileRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.stationProfiles,
          fromJson: StationProfile.fromJson,
        );
}

final stationProfileRepositoryProvider =
    Provider<StationProfileRepository>((ref) {
  return StationProfileRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
