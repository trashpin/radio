import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

const double _mile = 1609.344;

/// Distance → base priority band (nearer wins). Beyond 20 miles = 0.
int distanceBand(double meters) {
  final mi = meters / _mile;
  if (mi <= 1) return 100;
  if (mi <= 3) return 90;
  if (mi <= 5) return 80;
  if (mi <= 10) return 60;
  if (mi <= 20) return 40;
  return 0;
}

/// A master location paired with its live distance + score.
class NearbyLocation {
  const NearbyLocation(this.location, this.distanceMeters, this.score);
  final MasterLocation location;
  final double distanceMeters;
  final int score;
}

/// THE one Location Engine. A pure query layer over the master `locations`
/// dataset used by the Map, Explorer Radio, GPS triggers, "I See Something",
/// Nearby Explorer, Search, and Routes — so every location exists once and is
/// read the same way everywhere.
class LocationEngine {
  const LocationEngine();

  /// Locations to plot on the map: active, not hidden, has coordinates, and
  /// (optionally) within [maxMiles] of a center, filtered to [types].
  List<MasterLocation> mapLocations(
    List<MasterLocation> all, {
    double? centerLat,
    double? centerLng,
    double maxMiles = 20,
    Set<LocationType>? types,
  }) {
    return all.where((l) {
      if (!l.active || l.hidden || !l.hasCoordinates) return false;
      if (types != null && types.isNotEmpty && !types.contains(l.type)) {
        return false;
      }
      if (centerLat != null && centerLng != null) {
        final m = GeoMath.distanceMeters(
            centerLat, centerLng, l.latitude!, l.longitude!);
        final radius = l.mapVisibilityRadius ?? (maxMiles * _mile);
        if (m > radius) return false;
      }
      return true;
    }).toList();
  }

  /// Nearby locations for GPS / Radio / Nearby Explorer: within [maxMiles],
  /// ranked by distance band + the location's own priority, nearest-first.
  /// Honors active/hidden, category filter, and an exclude set (cooldown /
  /// already-played this trip).
  List<NearbyLocation> nearby(
    double latitude,
    double longitude,
    List<MasterLocation> all, {
    double maxMiles = 20,
    Set<LocationType>? types,
    Set<String> exclude = const {},
  }) {
    final out = <NearbyLocation>[];
    for (final l in all) {
      if (!l.active || l.hidden || !l.hasCoordinates) continue;
      if (exclude.contains(l.id)) continue;
      if (types != null && types.isNotEmpty && !types.contains(l.type)) continue;
      final m = GeoMath.distanceMeters(
          latitude, longitude, l.latitude!, l.longitude!);
      final band = distanceBand(m);
      final withinTrigger = l.triggerRadius != null && m <= l.triggerRadius!;
      if (band == 0 && !withinTrigger && m > maxMiles * _mile) continue;
      out.add(NearbyLocation(l, m, (band == 0 ? 40 : band) + l.priority));
    }
    out.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.distanceMeters.compareTo(b.distanceMeters);
    });
    return out;
  }

  /// The single highest-priority nearby location (Explorer Radio's pick).
  NearbyLocation? topNearby(
    double latitude,
    double longitude,
    List<MasterLocation> all, {
    double maxMiles = 20,
    Set<LocationType>? types,
    Set<String> exclude = const {},
  }) {
    final list = nearby(latitude, longitude, all,
        maxMiles: maxMiles, types: types, exclude: exclude);
    return list.isEmpty ? null : list.first;
  }

  /// Global search across every master location. Prefix matches rank above
  /// substring matches; ties broken by featured then priority.
  List<MasterLocation> search(String query, List<MasterLocation> all,
      {int limit = 25}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    int rank(MasterLocation l) {
      final name = l.name.toLowerCase();
      if (name == q) return 0;
      if (name.startsWith(q)) return 1;
      if (name.contains(q)) return 2;
      final meta = [
        l.type.label,
        l.county ?? '',
        l.city ?? '',
        l.community ?? '',
        l.description ?? '',
      ].join(' ').toLowerCase();
      if (meta.contains(q)) return 3;
      return 99;
    }

    final scored = all
        .where((l) => l.active && rank(l) < 99)
        .map((l) => (l, rank(l)))
        .toList()
      ..sort((a, b) {
        final byRank = a.$2.compareTo(b.$2);
        if (byRank != 0) return byRank;
        final byFeat = (b.$1.featured ? 1 : 0).compareTo(a.$1.featured ? 1 : 0);
        if (byFeat != 0) return byFeat;
        return b.$1.priority.compareTo(a.$1.priority);
      });
    return scored.take(limit).map((e) => e.$1).toList();
  }

  MasterLocation? byId(List<MasterLocation> all, String id) {
    for (final l in all) {
      if (l.id == id) return l;
    }
    return null;
  }
}
