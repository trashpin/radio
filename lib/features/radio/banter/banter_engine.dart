import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Where a banter clip sits in the local hierarchy, most specific first. The
/// engine prefers [park] over [city] over [county] when the user is inside
/// those places, and falls back down the list.
enum BanterScope { park, city, county }

/// A location chosen to supply a banter clip, tagged with the scope it filled.
class BanterCandidate {
  const BanterCandidate(this.location, this.scope, this.distanceMeters);
  final MasterLocation location;
  final BanterScope scope;
  final double distanceMeters;
}

/// Tuning for the banter engine — all data/config, no hard-coded places.
class BanterConfig {
  const BanterConfig({
    this.cooldown = const Duration(minutes: 20),
    this.parkRadiusMeters = 8046.72, // ~5 mi: "you're inside this park"
    this.cityRadiusMeters = 8046.72, // ~5 mi: "you're inside this town/city"
  });

  /// A given clip won't repeat until this long after it last played.
  final Duration cooldown;
  final double parkRadiusMeters;
  final double cityRadiusMeters;
}

/// THE Radio Banter Engine (pure, data-driven, unit-testable).
///
/// It builds a pool of eligible banter clips from the master `locations` around
/// the user — the park they're in, the city they're in, and the surrounding
/// county — then picks one to weave between songs, honoring:
///   • priority: park > city > county when inside those places,
///   • a cooldown so the same clip never repeats too soon,
///   • a fall-back to county-wide (e.g. Marion) banter when there's no
///     park/city clip available.
///
/// Everything is derived from location rows (county/city/type/content/GPS), so
/// new counties, cities and parks are added by adding data — no code changes.
/// Clip CONTENT is resolved elsewhere (reusing the AI narration/audio the
/// locations already carry); this engine only decides WHICH location speaks.
class BanterEngine {
  const BanterEngine([this.config = const BanterConfig()]);
  final BanterConfig config;

  /// Park-like containers a user can be "inside".
  static const Set<LocationType> parkTypes = {
    LocationType.statePark,
    LocationType.nationalPark,
    LocationType.countyPark,
    LocationType.cityPark,
    LocationType.nationalForest,
    LocationType.stateForest,
    LocationType.wildlifeManagementArea,
    LocationType.forest,
  };

  /// Populated-place containers a user can be "inside".
  static const Set<LocationType> cityTypes = {
    LocationType.city,
    LocationType.town,
    LocationType.village,
    LocationType.community,
    LocationType.neighborhood,
  };

  /// A location can supply banter only if it carries reusable spoken content
  /// (recorded audio, an AI narration script, or at least a description) and is
  /// visible to users (published, active, on the map, with coordinates).
  static bool hasBanterContent(MasterLocation l) =>
      l.audioFiles.any((u) => u.trim().isNotEmpty) ||
      (l.narrationScript ?? '').trim().isNotEmpty ||
      l.bestDescription != null;

  bool _eligible(MasterLocation l) =>
      l.active &&
      !l.hidden &&
      l.hasCoordinates &&
      !l.isPublishBlocked &&
      hasBanterContent(l);

  static String _norm(String? s) => (s ?? '').toLowerCase().trim();

  double _dist(double lat, double lng, MasterLocation l) =>
      GeoMath.distanceMeters(lat, lng, l.latitude!, l.longitude!);

  bool _within(double d, MasterLocation l, double fallbackRadius) =>
      d <= (l.triggerRadius ?? fallbackRadius);

  /// The park the user is currently inside (nearest park-type location whose
  /// radius contains them), or null.
  MasterLocation? currentPark(double lat, double lng, List<MasterLocation> all) {
    MasterLocation? best;
    var bestD = double.infinity;
    for (final l in all) {
      if (!parkTypes.contains(l.type) || !l.hasCoordinates) continue;
      final d = _dist(lat, lng, l);
      if (_within(d, l, config.parkRadiusMeters) && d < bestD) {
        best = l;
        bestD = d;
      }
    }
    return best;
  }

  /// The city/town the user is currently inside, or null.
  MasterLocation? currentCity(double lat, double lng, List<MasterLocation> all) {
    MasterLocation? best;
    var bestD = double.infinity;
    for (final l in all) {
      if (!cityTypes.contains(l.type) || !l.hasCoordinates) continue;
      final d = _dist(lat, lng, l);
      if (_within(d, l, config.cityRadiusMeters) && d < bestD) {
        best = l;
        bestD = d;
      }
    }
    return best;
  }

  /// Builds the eligible banter pool for the given position, tagged by scope.
  /// Restricted to [county] (case-insensitive) so we only ever talk about where
  /// the user actually is; when [county] is null the whole eligible set is used.
  List<BanterCandidate> buildPool(
    double lat,
    double lng,
    List<MasterLocation> all, {
    String? county,
  }) {
    final inCounty = [
      for (final l in all)
        if (_eligible(l) &&
            (county == null || _norm(l.county) == _norm(county)))
          l,
    ];
    final park = currentPark(lat, lng, all);
    final city = currentCity(lat, lng, all);
    final parkName = _norm(park?.name);
    final cityName = _norm(city?.name);

    // Scope by IDENTITY + explicit data fields (not raw proximity) so a large
    // park radius never swallows the surrounding city: a clip is park-scope
    // when it IS the current park or is tagged into it (community == park), and
    // city-scope when it IS the current city or carries that city on its row.
    // Everything else eligible in the county is county-scope. Fully data-driven.
    final out = <BanterCandidate>[];
    for (final l in inCounty) {
      final d = _dist(lat, lng, l);
      final BanterScope scope;
      if (park != null &&
          (l.id == park.id ||
              (parkName.isNotEmpty && _norm(l.community) == parkName))) {
        scope = BanterScope.park;
      } else if (city != null &&
          (l.id == city.id ||
              (cityName.isNotEmpty && _norm(l.city) == cityName))) {
        scope = BanterScope.city;
      } else {
        scope = BanterScope.county;
      }
      out.add(BanterCandidate(l, scope, d));
    }
    return out;
  }

  bool _inCooldown(String id, DateTime now, Map<String, DateTime> lastPlayed) {
    final at = lastPlayed[id];
    return at != null && now.difference(at) < config.cooldown;
  }

  /// Picks the next banter to play, honoring priority (park→city→county) and the
  /// cooldown. Within the highest-priority scope that has an available (not
  /// cooling-down) clip, it prefers the least-recently-played, breaking ties by
  /// nearest. Returns null when everything eligible is still cooling down.
  BanterCandidate? selectNext(
    double lat,
    double lng,
    List<MasterLocation> all, {
    required DateTime now,
    Map<String, DateTime> lastPlayed = const {},
    String? county,
  }) {
    final pool = buildPool(lat, lng, all, county: county);
    for (final scope in BanterScope.values) {
      final available = [
        for (final c in pool)
          if (c.scope == scope && !_inCooldown(c.location.id, now, lastPlayed)) c,
      ];
      if (available.isEmpty) continue;
      available.sort((a, b) {
        final la = lastPlayed[a.location.id];
        final lb = lastPlayed[b.location.id];
        if (la == null && lb != null) return -1;
        if (la != null && lb == null) return 1;
        if (la != null && lb != null && la != lb) return la.compareTo(lb);
        return a.distanceMeters.compareTo(b.distanceMeters);
      });
      return available.first;
    }
    return null;
  }
}
