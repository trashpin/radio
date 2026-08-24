import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Location types worth surfacing on the journey map — matches the spec's
/// own examples (Historic Site / Spring / Nature / Wildlife / Discovery).
/// Deliberately a small allow-list, not "every location" — reuses the SAME
/// `LocationType` taxonomy and `masterLocationsProvider` every other
/// location-aware feature in this app already reads; no new location data,
/// no duplicate records.
const _kJourneyRelevantTypes = {
  LocationType.historicSite,
  LocationType.historicDistrict,
  LocationType.spring,
  LocationType.waterfall,
  LocationType.wildlifeViewing,
  LocationType.wildlifeManagementArea,
  LocationType.statePark,
  LocationType.nationalPark,
  LocationType.countyPark,
  LocationType.cityPark,
  LocationType.forest,
  LocationType.nationalForest,
  LocationType.stateForest,
  LocationType.museum,
  LocationType.scenicOverlook,
  LocationType.attraction,
  LocationType.hiddenGem,
};

/// Within this radius of the player OR the destination, a relevant location
/// is worth showing as a "nearby discovery" on the journey map.
const double _kJourneyNearbyRadiusMeters = 8047; // ~5 miles

const int _kMaxJourneyNearby = 6;

/// Existing Marion County locations worth calling out during this leg of
/// the journey — near the player, near the destination, of a type the spec
/// itself names as interesting, and never the destination location itself
/// (avoids a duplicate marker sitting right on top of "NEXT DISCOVERY").
final journeyNearbyLocationsProvider = Provider.family<List<MasterLocation>,
    ({double playerLat, double playerLng, double destLat, double destLng, String? excludeLocationId})>(
  (ref, p) {
    final all = ref.watch(masterLocationsProvider).value ?? const [];
    final scored = <(MasterLocation, double)>[];
    for (final loc in all) {
      if (!loc.active || loc.hidden) continue;
      if (loc.id == p.excludeLocationId) continue;
      if (!_kJourneyRelevantTypes.contains(loc.type)) continue;
      final lat = loc.latitude;
      final lng = loc.longitude;
      if (lat == null || lng == null) continue;

      final distToPlayer = GeoMath.distanceMeters(p.playerLat, p.playerLng, lat, lng);
      final distToDest = GeoMath.distanceMeters(p.destLat, p.destLng, lat, lng);
      final closest = distToPlayer < distToDest ? distToPlayer : distToDest;
      if (closest > _kJourneyNearbyRadiusMeters) continue;
      scored.add((loc, closest));
    }
    scored.sort((a, b) => a.$2.compareTo(b.$2));
    return scored.take(_kMaxJourneyNearby).map((e) => e.$1).toList();
  },
);
