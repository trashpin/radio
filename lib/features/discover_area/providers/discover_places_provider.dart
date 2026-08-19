import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/events/data/event_repository.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/location_engine.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/nearby_gems/data/nearby_gems_repository.dart';

/// DISCOVER's six fixed categories, always shown in this order: GEMS, EVENTS,
/// LOCAL PARKS, MUSEUMS & HISTORICAL POINTS, SPRINGS, STATE PARKS.
///
/// Every provider below reads the exact same master `locations`/`events`/
/// `nearby_gems` Supabase tables every other feature already reads (no new
/// content system) and ranks with the exact same [GeoMath.distanceMeters]
/// great-circle distance Radio/Explore/Map already use (no new GPS/distance
/// system). The only thing new here is that these providers are COUNTY-WIDE:
/// they drop the radius caps other surfaces use (Gems: 5/10mi, Events/Parks/
/// Attractions: 20mi) in favor of a full Marion-County pool sorted nearest
/// first — distance sorts, it doesn't eliminate.
const Set<LocationType> discoverLocalParkTypes = {
  LocationType.countyPark,
  LocationType.cityPark,
};
const Set<LocationType> discoverStateParkTypes = {
  LocationType.statePark,
  LocationType.nationalPark,
};
const Set<LocationType> discoverSpringTypes = {LocationType.spring};
const Set<LocationType> discoverMuseumHistoricTypes = {
  LocationType.museum,
  LocationType.historicSite,
  LocationType.historicDistrict,
  LocationType.attraction,
  LocationType.pointOfInterest,
  LocationType.scenicOverlook,
  LocationType.hiddenGem,
};

/// Kept for a blank/unset county (sparse data shouldn't disappear) or one
/// that matches Marion; excludes only rows definitively tagged with a
/// different county.
bool isMarionOrUnset(String? county) {
  final c = (county ?? '').toLowerCase().trim();
  return c.isEmpty || c == 'marion';
}

/// County-wide (no radius cap), type-filtered, nearest-first master
/// locations for one DISCOVER category. Pure and unit-testable.
List<NearbyLocation> discoverLocationsOfTypes(
  List<MasterLocation> all,
  Set<LocationType> types, {
  required double lat,
  required double lng,
}) {
  final out = <NearbyLocation>[];
  for (final l in all) {
    if (!types.contains(l.type)) continue;
    if (!l.active || l.hidden || !l.hasCoordinates) continue;
    if (l.isPublishBlocked) continue;
    if (!isMarionOrUnset(l.county)) continue;
    final d = GeoMath.distanceMeters(lat, lng, l.latitude!, l.longitude!);
    out.add(NearbyLocation(l, d, 0));
  }
  out.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return out;
}

final discoverLocalParksProvider = Provider<List<NearbyLocation>>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return const [];
  final all = ref.watch(masterLocationsProvider).value ?? const [];
  return discoverLocationsOfTypes(all, discoverLocalParkTypes,
      lat: center.latitude, lng: center.longitude);
});

final discoverStateParksProvider = Provider<List<NearbyLocation>>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return const [];
  final all = ref.watch(masterLocationsProvider).value ?? const [];
  return discoverLocationsOfTypes(all, discoverStateParkTypes,
      lat: center.latitude, lng: center.longitude);
});

final discoverSpringsProvider = Provider<List<NearbyLocation>>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return const [];
  final all = ref.watch(masterLocationsProvider).value ?? const [];
  return discoverLocationsOfTypes(all, discoverSpringTypes,
      lat: center.latitude, lng: center.longitude);
});

final discoverMuseumsHistoricProvider = Provider<List<NearbyLocation>>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return const [];
  final all = ref.watch(masterLocationsProvider).value ?? const [];
  return discoverLocationsOfTypes(all, discoverMuseumHistoricTypes,
      lat: center.latitude, lng: center.longitude);
});

/// County-wide gems, nearest-first — same [rankNearbyGems] editorial
/// ranking (featured > priority > popularity, distance as the tiebreaker)
/// the rest of the Gems feature uses, just without
/// [nearbyGemsRadiusProvider]'s 5/10mi cap.
final discoverGemsProvider = Provider<List<NearbyGemHit>>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return const [];
  final gems = ref.watch(activeNearbyGemsProvider).value ?? const [];
  final hits = <NearbyGemHit>[];
  for (final g in gems) {
    if (!g.hasCoordinates) continue;
    final m = GeoMath.distanceMeters(
        center.latitude, center.longitude, g.latitude!, g.longitude!);
    hits.add(NearbyGemHit(g, m));
  }
  return rankNearbyGems(hits);
});

/// County-wide, non-expired events, nearest-first — reuses the Event
/// Engine's own expiry rule (an event drops off once its `eventDate` is
/// before today), just without [nearbyEventsProvider]'s 20mi cap.
final discoverEventsProvider = Provider<List<NearbyEvent>>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return const [];
  final all = ref.watch(eventsProvider).value ?? const [];
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final out = <NearbyEvent>[];
  for (final e in all) {
    if (!e.hasCoordinates) continue;
    if (e.eventDate != null && e.eventDate!.isBefore(todayDate)) continue;
    if (!isMarionOrUnset(e.county)) continue;
    final d = GeoMath.distanceMeters(
        center.latitude, center.longitude, e.latitude!, e.longitude!);
    out.add(NearbyEvent(e, d));
  }
  out.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return out;
});
