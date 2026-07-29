import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';

/// Bridges the master `locations` table into the app's existing [NearbyItem]
/// shape so the Map, Around Me, and the Radio content pool can all read the ONE
/// database without each consumer being rewritten. This is the Phase-2 cutover
/// seam: when the master table has data (migration 0031 applied), every
/// location surface reads from it; before that it stays empty and legacy
/// sources continue to feed the app unchanged.

/// Existing category token (used by marker styling + Around Me grouping) for a
/// master [LocationType]. Falls back to the type id, which the map's category
/// inference resolves by keyword.
String nearbyTokenFor(LocationType t) {
  switch (t) {
    case LocationType.spring:
      return 'springs';
    case LocationType.trail:
    case LocationType.trailhead:
      return 'trails';
    case LocationType.historicSite:
    case LocationType.historicDistrict:
      return 'historic_sites';
    case LocationType.scenicOverlook:
      return 'scenic_overlooks';
    case LocationType.visitorCenter:
      return 'visitor_centers';
    case LocationType.boatRamp:
      return 'boat_ramps';
    case LocationType.campground:
      return 'campgrounds';
    case LocationType.parking:
      return 'parking';
    case LocationType.wildlifeViewing:
      return 'wildlife';
    case LocationType.county:
    case LocationType.city:
    case LocationType.community:
      return 'cities';
    default:
      return t.id;
  }
}

NearbyItem masterToNearby(MasterLocation l) => NearbyItem(
      id: 'locations:${l.id}',
      category: nearbyTokenFor(l.type),
      name: l.name,
      latitude: l.latitude!,
      longitude: l.longitude!,
      subcategory: l.type.label,
      description: l.description,
      imageUrl: l.images.isNotEmpty ? l.images.first : null,
      audioUrl: l.audioFiles.isNotEmpty ? l.audioFiles.first : null,
      parkCode: l.destinationCode,
      featured: l.featured,
    );

/// Master locations as plottable [NearbyItem]s (active, visible, geo-coded).
/// Empty until migration 0031 is applied — callers then fall back to legacy.
final masterNearbyItemsProvider = Provider<List<NearbyItem>>((ref) {
  final all = ref.watch(masterLocationsProvider).value ?? const [];
  return [
    for (final l in all)
      if (l.active && !l.hidden && l.hasCoordinates) masterToNearby(l),
  ];
});
