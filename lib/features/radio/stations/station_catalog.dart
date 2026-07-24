import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/radio/models/station_profile.dart';
import 'package:explorer_os_mobile/features/radio/repositories/station_profile_repository.dart';
import 'package:explorer_os_mobile/features/radio/stations/default_stations.dart';

/// Loads the catalog of station profiles, falling back to the built-in seed.
///
/// WHY THIS EXISTS: the app should always have stations to offer — even offline
/// or on first run. This service reads backend profiles and, if none are
/// available, returns [defaultStationProfiles]. The rest of the app treats the
/// catalog as data-driven regardless of source.
class StationCatalog {
  const StationCatalog(this._repository);

  final StationProfileRepository _repository;

  Future<List<StationProfile>> load() async {
    final profiles = await _repository.getAll();
    return profiles.isEmpty ? defaultStationProfiles : profiles;
  }
}

final stationCatalogProvider = Provider<StationCatalog>((ref) {
  return StationCatalog(ref.watch(stationProfileRepositoryProvider));
});

/// The resolved station catalog (backend or seed).
final stationCatalogListProvider =
    FutureProvider<List<StationProfile>>((ref) {
  return ref.watch(stationCatalogProvider).load();
});
