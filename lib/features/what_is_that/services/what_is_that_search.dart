import 'package:explorer_os_mobile/features/gps/models/attraction_point.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/services/upcoming_destination_service.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/what_is_that/models/what_is_that_candidate.dart';

/// Location types "What Is That?" will consider — physical, point-at-able
/// landmarks and places, deliberately broader than Explore's own
/// `_kEligibleHeadedTypes` (which is scoped to what the radio ROTATION reads
/// out loud while driving). This is its own, independent list — a separate,
/// isolated feature, not a shared filter with Explore.
const Set<LocationType> kWhatIsThatEligibleTypes = {
  LocationType.statePark,
  LocationType.nationalPark,
  LocationType.countyPark,
  LocationType.cityPark,
  LocationType.nationalForest,
  LocationType.stateForest,
  LocationType.spring,
  LocationType.lake,
  LocationType.river,
  LocationType.waterfall,
  LocationType.historicSite,
  LocationType.historicDistrict,
  LocationType.museum,
  LocationType.attraction,
  LocationType.scenicOverlook,
  LocationType.monument,
  LocationType.memorial,
  LocationType.lighthouse,
  LocationType.bridge,
  LocationType.cave,
  LocationType.beach,
  LocationType.wildlifeViewing,
  LocationType.hiddenGem,
  LocationType.localAttraction,
  LocationType.town,
  LocationType.city,
  LocationType.community,
  LocationType.village,
};

/// Pure, synchronous directional search: which known [locations] fall within
/// a cone of [headingDegrees] from [userLocation]? Reuses the EXACT same
/// [UpcomingDestinationService] cone+radius+ETA detector the GPS engine
/// already uses elsewhere (`explore_providers.dart`'s `_aheadCandidates`) —
/// no new geometry, just a different (broader, non-Explore) type filter and
/// a richer result shape (image/description/audio) for this screen's own
/// use. No I/O, no side effects — everything needed is passed in.
List<WhatIsThatCandidate> findWhatIsThatCandidates({
  required List<MasterLocation> locations,
  required GPSLocation userLocation,
  required double headingDegrees,
  double coneDegrees = 50,
  double radiusMeters = 8046.72, // 5 miles
  int limit = 6,
  Set<LocationType> eligibleTypes = kWhatIsThatEligibleTypes,
}) {
  final points = <AttractionPoint>[];
  final byId = <String, MasterLocation>{};
  for (final loc in locations) {
    if (!loc.active || loc.hidden) continue;
    if (!eligibleTypes.contains(loc.type)) continue;
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
    limit: limit,
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
    ));
  }
  return out;
}
