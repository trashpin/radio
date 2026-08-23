import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/providers/discover_places_provider.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';
import 'package:explorer_os_mobile/features/events/data/event_repository.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/nearby_gems/data/nearby_gems_repository.dart';
import 'package:explorer_os_mobile/features/radio/services/player_location_context.dart';

/// Marion County's approximate center (Ocala, FL) — used ONLY as a distance
/// reference point when no real GPS fix exists yet, so "distance" still
/// sorts sensibly and NEAR YOU never has to block on location permission
/// (spec: "Do not require location permission for the entire feature to
/// work... fall back to Marion County-wide recommendations"). The category
/// pools themselves are already county-wide and uncapped by radius
/// regardless of which center is used — this only affects sort order.
const _fallbackLat = 29.1872;
const _fallbackLng = -82.1401;

/// True once a real GPS fix exists — exposed so the UI can show "Marion
/// County-wide" instead of implying real distances when there's no fix yet.
final discoverHasRealLocationProvider = Provider<bool>((ref) {
  return ref.watch(mapCenterProvider) != null;
});

/// Every recommendable item across Marion County, normalized. Reuses the
/// exact same content pools `discover_places_provider.dart` already exposes
/// (themselves reading `nearby_gems`/`events`/`locations` — no duplicate
/// content fetch, no duplicate database) — just re-centered on Marion
/// County's centroid when no real GPS fix exists yet, rather than returning
/// nothing.
final discoverAllItemsProvider = Provider<List<DiscoverableItem>>((ref) {
  final center = ref.watch(mapCenterProvider);
  final lat = center?.latitude ?? _fallbackLat;
  final lng = center?.longitude ?? _fallbackLng;

  final allLocations = ref.watch(masterLocationsProvider).value ?? const [];
  final allEvents = ref.watch(eventsProvider).value ?? const [];
  // Discover's GEMS/FOOD content is scoped to restaurants specifically — the
  // Nearby Gems system itself is untouched (still admin-curated, still spans
  // coffee/shopping/attractions/etc. for its own screen); Discover just only
  // ever surfaces the restaurant-category subset of it.
  final allGems = (ref.watch(activeNearbyGemsProvider).value ?? const [])
      .where((g) => (g.category ?? '').trim().toLowerCase() == 'restaurant')
      .toList();

  final localParks =
      discoverLocationsOfTypes(allLocations, discoverLocalParkTypes, lat: lat, lng: lng);
  final stateParks =
      discoverLocationsOfTypes(allLocations, discoverStateParkTypes, lat: lat, lng: lng);
  final springs = discoverLocationsOfTypes(allLocations, discoverSpringTypes, lat: lat, lng: lng);
  final museumsHistoric =
      discoverLocationsOfTypes(allLocations, discoverMuseumHistoricTypes, lat: lat, lng: lng);

  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);

  final gemHits = <NearbyGemHit>[];
  for (final g in allGems) {
    if (!g.hasCoordinates) continue;
    final d = GeoMath.distanceMeters(lat, lng, g.latitude!, g.longitude!);
    gemHits.add(NearbyGemHit(g, d));
  }

  final eventHits = <NearbyEvent>[];
  for (final e in allEvents) {
    if (!e.hasCoordinates) continue;
    if (e.eventDate != null && e.eventDate!.isBefore(todayDate)) continue;
    final d = GeoMath.distanceMeters(lat, lng, e.latitude!, e.longitude!);
    eventHits.add(NearbyEvent(e, d));
  }

  return [
    for (final g in rankNearbyGems(gemHits)) discoverItemFromGemHit(g),
    for (final e in eventHits) discoverItemFromEvent(e),
    for (final n in localParks) discoverItemFromLocation(PlayerLocationKind.park, n),
    for (final n in museumsHistoric) discoverItemFromLocation(PlayerLocationKind.attraction, n),
    for (final n in springs) discoverItemFromLocation(PlayerLocationKind.spring, n),
    for (final n in stateParks) discoverItemFromLocation(PlayerLocationKind.park, n),
  ];
});
