/// The 11-level geofence hierarchy, deepest last. [depth] is what "deepest
/// boundary always wins" compares — a POI (depth 10) always outranks a
/// County (depth 1) the traveler happens to also be standing inside,
/// regardless of priority.
enum GeofenceLevel {
  state('state', 'State', 0, 20),
  county('county', 'County', 1, 40),
  city('city', 'City', 2, 60),
  district('district', 'District', 3, 65),
  neighborhood('neighborhood', 'Neighborhood', 4, 70),
  park('park', 'Park', 5, 80),
  business('business', 'Business', 6, 82),
  trail('trail', 'Trail', 7, 85),
  historicSite('historic_site', 'Historic Site', 8, 90),
  museum('museum', 'Museum', 9, 95),
  poi('poi', 'Point of Interest', 10, 100);

  const GeofenceLevel(this.id, this.label, this.depth, this.defaultPriority);

  final String id;
  final String label;

  /// Higher = deeper in the hierarchy = wins over anything shallower,
  /// regardless of priority. Matches migration 0043's insertion order.
  final int depth;

  /// Default cross-type priority (matches `geofence_level_defaults`) — used
  /// as the tiebreak among several geofences at the SAME depth (e.g. two
  /// overlapping POIs). A specific geofence's `priorityOverride` wins over
  /// this when set.
  final int defaultPriority;

  static GeofenceLevel? fromId(String? id) {
    for (final level in GeofenceLevel.values) {
      if (level.id == id) return level;
    }
    return null;
  }
}
