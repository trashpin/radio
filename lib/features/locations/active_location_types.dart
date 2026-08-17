import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// THE allow-list that scopes the whole app to a curated set of location types
/// while we perfect them. At this stage ExplorerOS only imports, displays, and
/// narrates FIVE tiers:
///
///   1. County                       (LocationType.county)
///   2. City / Community             (city, town, village, community, neighborhood)
///   3. City Park                    (cityPark)
///   4. Florida State Park           (statePark)
///   5. Spring                       (spring)
///
/// Everything else (restaurants, gas, shops, museums, trails, lakes, historic
/// sites, hidden gems, events, …) is intentionally excluded from import, the
/// map, Nearby, and narration until it's ready.
///
/// To add a category later you ONLY edit this file — every surface reads from
/// [isActiveLocationType] / [LocationTier], so nothing else needs to change.
enum LocationTier {
  county,
  city,
  park,
  statePark,
  spring,
}

/// The tier a type belongs to, or null if the type is NOT currently active.
/// The enum order is also the narration priority (county first).
LocationTier? locationTierOf(LocationType t) {
  switch (t) {
    case LocationType.county:
      return LocationTier.county;
    case LocationType.city:
    case LocationType.town:
    case LocationType.village:
    case LocationType.community:
    case LocationType.neighborhood:
      return LocationTier.city;
    case LocationType.cityPark:
      return LocationTier.park;
    case LocationType.statePark:
      return LocationTier.statePark;
    case LocationType.spring:
      return LocationTier.spring;
    default:
      return null;
  }
}

/// The exact set of types allowed right now (derived from [locationTierOf]).
final Set<LocationType> kActiveLocationTypes = {
  for (final t in LocationType.values)
    if (locationTierOf(t) != null) t,
};

/// Whether a type is part of the current curated experience.
bool isActiveLocationType(LocationType t) => locationTierOf(t) != null;

/// Narration priority (lower = narrated first): County ▸ City ▸ Park ▸ State
/// Park ▸ Spring. Non-active types return a very low priority so they can never
/// win a narration slot.
int narrationPriority(LocationType t) => locationTierOf(t)?.index ?? 999;

/// Keep only active-type locations — the one call every user-facing surface
/// (map, Nearby, narration, banter) uses to enforce the allow-list.
List<MasterLocation> onlyActiveTypes(List<MasterLocation> all) =>
    [for (final l in all) if (isActiveLocationType(l.type)) l];
