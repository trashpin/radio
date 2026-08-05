import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Location types that count as an "attraction" for Discover This Area,
/// per the spec: museums, parks, historic sites, trails, scenic overlooks,
/// hidden gems.
const _attractionTypes = {
  LocationType.museum,
  LocationType.statePark,
  LocationType.nationalPark,
  LocationType.countyPark,
  LocationType.historicSite,
  LocationType.historicDistrict,
  LocationType.trail,
  LocationType.trailhead,
  LocationType.scenicOverlook,
  LocationType.hiddenGem,
};

/// One attraction match, with its distance from the area's center.
class AttractionMatch {
  const AttractionMatch({required this.location, required this.distanceMeters});
  final MasterLocation location;
  final double distanceMeters;
}

/// Finds attraction-type locations near [area], nearest first. Excludes the
/// area's own record (an area shouldn't list itself), inactive/hidden rows,
/// and anything without coordinates. Pure — no I/O, easy to unit test.
List<AttractionMatch> nearbyAttractions(
  List<MasterLocation> allLocations,
  MasterLocation area, {
  double radiusMeters = 8000,
  int limit = 30,
}) {
  if (!area.hasCoordinates) return const [];
  final matches = <AttractionMatch>[];
  for (final l in allLocations) {
    if (l.id == area.id) continue;
    if (!_attractionTypes.contains(l.type)) continue;
    if (!l.active || l.hidden || !l.hasCoordinates) continue;
    if (l.isPublishBlocked) continue;
    final distance = GeoMath.distanceMeters(
      area.latitude!,
      area.longitude!,
      l.latitude!,
      l.longitude!,
    );
    if (distance > radiusMeters) continue;
    matches.add(AttractionMatch(location: l, distanceMeters: distance));
  }
  matches.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return matches.take(limit).toList(growable: false);
}
