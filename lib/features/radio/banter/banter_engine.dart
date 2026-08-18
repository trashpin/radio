import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/locations/active_location_types.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// A location chosen to supply a banter clip, tagged with its tier + distance.
class BanterCandidate {
  const BanterCandidate(this.location, this.tier, this.distanceMeters);
  final MasterLocation location;
  final LocationTier tier;
  final double distanceMeters;
}

/// Tuning for the banter engine — all data/config, no hard-coded places.
class BanterConfig {
  const BanterConfig({
    this.cooldown = const Duration(minutes: 20),
    this.cityRadiusMeters = 8046.72, // ~5 mi: "you're inside this city/community"
    this.nearbyRadiusMeters = 16093.4, // ~10 mi: a "nearby" park / state park / spring
  });

  /// A clip won't repeat until this long after it last played.
  final Duration cooldown;
  final double cityRadiusMeters;
  final double nearbyRadiusMeters;
}

/// THE Radio Banter Engine (pure, data-driven, unit-testable).
///
/// Scoped to the active tiers only (county, city/community, city park,
/// Florida state park, spring, museum — see [locationTierOf]); nothing else
/// is ever eligible. For the user's position it builds a pool of clips from
/// the master `locations` in the current county — the county itself, the
/// city/community they're inside, and NEARBY parks / state parks / springs /
/// museums — then picks one to weave between songs, honoring:
///   • narration priority County ▸ City ▸ Park ▸ State Park ▸ Spring ▸ Museum,
///   • a cooldown so the same clip never repeats too soon.
///
/// Everything is derived from location rows (type/county/content/GPS), so new
/// counties/cities/parks/springs are added by adding data. Clip CONTENT is
/// resolved elsewhere, reusing the AI narration/audio each location carries.
class BanterEngine {
  const BanterEngine([this.config = const BanterConfig()]);
  final BanterConfig config;

  /// A location can supply banter only if it's an ACTIVE tier, carries reusable
  /// spoken content (audio, AI narration script, or a description), and is
  /// visible to users (published, active, on the map, with coordinates).
  static bool hasBanterContent(MasterLocation l) =>
      l.audioFiles.any((u) => u.trim().isNotEmpty) ||
      (l.narrationScript ?? '').trim().isNotEmpty ||
      l.bestDescription != null;

  bool _eligible(MasterLocation l) =>
      isActiveLocationType(l.type) &&
      l.active &&
      !l.hidden &&
      l.hasCoordinates &&
      !l.isPublishBlocked &&
      hasBanterContent(l);

  static String _norm(String? s) => (s ?? '').toLowerCase().trim();

  double _dist(double lat, double lng, MasterLocation l) =>
      GeoMath.distanceMeters(lat, lng, l.latitude!, l.longitude!);

  /// The city/community the user is currently inside (nearest city-tier
  /// location whose radius contains them), or null.
  MasterLocation? currentCity(double lat, double lng, List<MasterLocation> all) {
    MasterLocation? best;
    var bestD = double.infinity;
    for (final l in all) {
      if (locationTierOf(l.type) != LocationTier.city || !l.hasCoordinates) {
        continue;
      }
      final d = _dist(lat, lng, l);
      if (d <= (l.triggerRadius ?? config.cityRadiusMeters) && d < bestD) {
        best = l;
        bestD = d;
      }
    }
    return best;
  }

  /// Builds the eligible banter pool for the position, restricted to [county]
  /// (case-insensitive; null = no county filter). Per the spec, includes: the
  /// county, the city/community the user is IN, and NEARBY parks / state parks
  /// / springs.
  List<BanterCandidate> buildPool(
    double lat,
    double lng,
    List<MasterLocation> all, {
    String? county,
  }) {
    final city = currentCity(lat, lng, all);
    final out = <BanterCandidate>[];
    for (final l in all) {
      if (!_eligible(l)) continue;
      if (county != null && _norm(l.county) != _norm(county)) continue;
      final tier = locationTierOf(l.type)!;
      final d = _dist(lat, lng, l);
      final bool relevant;
      switch (tier) {
        case LocationTier.county:
          relevant = true; // it's the county you're in
        case LocationTier.city:
          relevant = city != null && l.id == city.id; // the city you're in
        case LocationTier.park:
        case LocationTier.statePark:
        case LocationTier.spring:
        case LocationTier.museum:
          relevant = d <= config.nearbyRadiusMeters; // nearby
      }
      if (relevant) out.add(BanterCandidate(l, tier, d));
    }
    return out;
  }

  bool _inCooldown(String id, DateTime now, Map<String, DateTime> lastPlayed) {
    final at = lastPlayed[id];
    return at != null && now.difference(at) < config.cooldown;
  }

  /// Picks the next banter, honoring the tier priority (County ▸ City ▸ Park ▸
  /// State Park ▸ Spring) and the cooldown. Within the highest-priority tier
  /// that has an available (not cooling-down) clip, prefers the least-recently-
  /// played, breaking ties by nearest. Returns null when everything is cooling
  /// down or nothing is eligible.
  BanterCandidate? selectNext(
    double lat,
    double lng,
    List<MasterLocation> all, {
    required DateTime now,
    Map<String, DateTime> lastPlayed = const {},
    String? county,
  }) {
    final pool = buildPool(lat, lng, all, county: county);
    for (final tier in LocationTier.values) {
      final available = [
        for (final c in pool)
          if (c.tier == tier && !_inCooldown(c.location.id, now, lastPlayed)) c,
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
