import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/discover_area/models/nearby_attractions.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';

/// Attractions (museums, parks, historic sites, trails, scenic overlooks,
/// hidden gems) near [area], nearest first.
final areaAttractionsProvider =
    Provider.family<List<AttractionMatch>, DiscoveryArea>((ref, area) {
  final all = ref.watch(masterLocationsProvider).value ?? const [];
  return nearbyAttractions(all, area.location);
});
