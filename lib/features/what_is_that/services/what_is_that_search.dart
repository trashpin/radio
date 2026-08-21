import 'package:explorer_os_mobile/features/gps/models/attraction_point.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/services/upcoming_destination_service.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/what_is_that/models/what_is_that_candidate.dart';

/// Location types "What Is That?" deliberately EXCLUDES — pure utility/
/// administrative entries that are never what someone is pointing at ("what
/// is that [building/lake/park/etc.] over there"), plus diffuse regions with
/// no single point-at-able location (a county/state/country/neighborhood
/// doesn't have "a spot" the way a building or lake does). Everything else
/// in the shared `LocationType` taxonomy is eligible — spec: "continue using
/// ALL of our existing location/content categories." An allow-list would
/// need updating every time a new type is added to the app; a short
/// block-list doesn't. This is its own, independent filter — a separate,
/// isolated feature, not a shared filter with Explore's own
/// `_kEligibleHeadedTypes` (which is scoped to what the radio ROTATION reads
/// out loud while driving, a different concern).
const Set<LocationType> kWhatIsThatExcludedTypes = {
  LocationType.gasStation,
  LocationType.parking,
  LocationType.safetyAlert,
  LocationType.county,
  LocationType.state,
  LocationType.country,
  LocationType.area,
  LocationType.neighborhood,
};

/// Deprecated name kept only so any external reference (tests, tools) that
/// still wants "the eligible set" can compute it; the search itself now
/// filters via [kWhatIsThatExcludedTypes] directly.
Set<LocationType> get kWhatIsThatEligibleTypes => {
      for (final t in LocationType.values)
        if (!kWhatIsThatExcludedTypes.contains(t)) t,
    };

/// How many raw in-cone candidates to rank before trimming to the final
/// result — wider than the final `limit` so a relevance re-sort (below) has
/// real choices to work with instead of just whatever
/// [UpcomingDestinationService] happened to return nearest-first.
const int _kCandidatePoolSize = 15;

/// Pure, synchronous directional search: which known [locations] fall within
/// a cone of [headingDegrees] from [userLocation]? Reuses the EXACT same
/// [UpcomingDestinationService] cone+radius+ETA detector the GPS engine
/// already uses elsewhere (`explore_providers.dart`'s `_aheadCandidates`) —
/// no new geometry, one unified search for every category (buildings,
/// historic sites, water features, parks, ...), just a broader type filter
/// and a richer result shape (image/description/audio) for this screen's
/// own use, then a light relevance re-rank on top of the raw distance order
/// so a well-known, admin-curated landmark isn't crowded out by a slightly
/// closer but low-value entry. No I/O, no side effects — everything needed
/// is passed in.
List<WhatIsThatCandidate> findWhatIsThatCandidates({
  required List<MasterLocation> locations,
  required GPSLocation userLocation,
  required double headingDegrees,
  double coneDegrees = 50,
  double radiusMeters = 8046.72, // 5 miles
  int limit = 3, // spec: "show the best 2-3 choices"
  Set<LocationType> excludedTypes = kWhatIsThatExcludedTypes,
}) {
  final points = <AttractionPoint>[];
  final byId = <String, MasterLocation>{};
  for (final loc in locations) {
    if (!loc.active || loc.hidden) continue;
    if (excludedTypes.contains(loc.type)) continue;
    final lat = loc.latitude;
    final lng = loc.longitude;
    if (lat == null || lng == null) continue;
    final id = 'loc:${loc.id}';
    points.add(AttractionPoint(id: id, name: loc.name, latitude: lat, longitude: lng));
    byId[id] = loc;
  }
  if (points.isEmpty) return const [];

  final results = const UpcomingDestinationService().search(
    points,
    userLocation,
    headingDegrees,
    coneDegrees: coneDegrees,
    radiusMeters: radiusMeters,
    limit: _kCandidatePoolSize,
  );

  final out = <WhatIsThatCandidate>[];
  for (final r in results) {
    final loc = byId[r.id];
    if (loc == null) continue;
    out.add(WhatIsThatCandidate(
      id: r.id,
      name: r.name,
      locationId: loc.id,
      latitude: r.latitude,
      longitude: r.longitude,
      distanceMeters: r.distanceMeters,
      bearingDegrees: r.bearingDegrees,
      imageUrl: loc.images.isNotEmpty ? loc.images.first : null,
      description: loc.bestDescription,
      audioUrl: loc.hasAudio ? loc.audioFiles.first : null,
      typeLabel: loc.type.label,
      address: loc.address,
      hours: loc.hours,
      admission: loc.admission,
      wheelchairAccessible: loc.wheelchairAccessible,
      relevanceScore: _relevanceScore(loc, r.distanceMeters),
    ));
  }
  out.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
  return out.take(limit).toList(growable: false);
}

/// "distance + location relevance" (spec) as one blended score, higher is
/// better: distance alone (converted to a 0-1-ish closeness figure) plus a
/// bounded boost for admin-curated significance (`featured`/`priority`),
/// scaled small enough that a genuinely much-closer plain entry still wins
/// over a far-away featured one — the boost only matters as a tie-breaker
/// among candidates that are already roughly comparable in distance.
double _relevanceScore(MasterLocation loc, double distanceMeters) {
  final closeness = 1 / (1 + distanceMeters / 400); // ~400m half-value point
  final featuredBoost = loc.featured ? 0.15 : 0.0;
  final priorityBoost = (loc.priority.clamp(0, 100)) / 100 * 0.1;
  return closeness + featuredBoost + priorityBoost;
}
