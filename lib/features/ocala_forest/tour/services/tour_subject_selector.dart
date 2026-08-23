import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_experience_controller.dart'
    show kForestDefaultGeofenceMeters;
import 'package:explorer_os_mobile/features/ocala_forest/discover/services/nearest_trail_finder.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/forest_around_me_providers.dart'
    show kForestAroundMeRadiusMeters;
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_story_type.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_subject.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_type.dart';

/// Pure "what should the guide talk about next" logic — no Riverpod, no
/// I/O, no GPS/geofence code of its own. Distance tiers are plain
/// `GeoMath.distanceMeters`/`nearestTrailId` checks — the SAME helpers
/// every other forest feature already uses, not a new geofence system;
/// [ForestTourEngine] is what decides WHEN a fresh ranking is even
/// consulted (arrival/trail-change + cooldown), this class only decides
/// WHICH candidate wins once that happens.
///
/// Ranking directly implements spec §8's relevance stars: an exact
/// geofence match outranks a merely-nearby one, which outranks being on a
/// trail, which outranks a nearby trail, which outranks a farther-but-
/// still-in-range location, which outranks the general fallback. A
/// visitor standing inside a specific historic geofence must never get a
/// random story from across the forest instead (spec §5) — ranking by
/// real distance against real geofence radii is what guarantees that.
class TourSubjectSelector {
  const TourSubjectSelector();

  /// A location within this radius (but outside its own configured
  /// geofence) still counts as "nearby geofence" (spec §4/§8 tier 2).
  static const double kNearGeofenceMeters = 300;

  /// Within this distance of a trail's geometry counts as "on/current
  /// trail" (spec §8 tier 2, tied with "nearby geofence").
  static const double kOnTrailMeters = 60;

  /// Within this distance counts as "nearby trail" (spec §8 tier 3) even
  /// if not literally on it.
  static const double kNearTrailMeters = 500;

  /// Beyond this, a location/trail no longer counts as relevant to "where
  /// the visitor currently is" at all (spec §13: "Tell Me Something"
  /// must never reach across the whole 383,000-acre forest for content) —
  /// the same 5-mile radius `forestAroundMeExperiencesProvider` already
  /// uses for "nearby" in this app.
  static const double kMaxRelevantMeters = kForestAroundMeRadiusMeters;

  /// Ranks every eligible, not-recently-discussed candidate and returns
  /// the single best one — or null if genuinely nothing is within range
  /// (callers fall back to [TourSubject.general] themselves when they need
  /// a guaranteed non-null result; see [ForestTourEngine.onDemand]).
  TourSubject? rank({
    required double lat,
    required double lng,
    required List<ForestLocation> locations,
    required List<ForestTrail> trails,
    required Set<String> recentlyDiscussedIds,
    TourType tourType = TourType.general,
  }) {
    final candidates = <(TourSubject subject, double score, double distance)>[];

    for (final l in _eligibleLocations(locations, tourType)) {
      if (recentlyDiscussedIds.contains(l.id)) continue;
      final dist = GeoMath.distanceMeters(lat, lng, l.latitude, l.longitude);
      if (dist > kMaxRelevantMeters) continue;
      final ownRadius = l.geofenceRadiusMeters ?? kForestDefaultGeofenceMeters;
      final isExact = dist <= ownRadius;
      final score = isExact
          ? 5.0 // exact active geofence
          : (dist <= kNearGeofenceMeters ? 4.0 : 2.0); // nearby geofence / nearby location
      candidates.add((TourSubject.forLocation(l, isExactMatch: isExact), score, dist));
    }

    for (final t in trails) {
      if (recentlyDiscussedIds.contains(t.id)) continue;
      if (t.parts.isEmpty) continue;
      final onTrailId = nearestTrailId(lat, lng, [t], maxMeters: kOnTrailMeters);
      final nearTrailId = nearestTrailId(lat, lng, [t], maxMeters: kNearTrailMeters);
      if (onTrailId == null && nearTrailId == null) continue;
      final isExact = onTrailId != null;
      final dist = isExact ? 0.0 : kOnTrailMeters + 1;
      final score = isExact ? 4.0 : 3.0; // current trail / nearby trail
      candidates.add((TourSubject.forTrail(t, isExactMatch: isExact), score, dist));
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : a.$3.compareTo(b.$3);
    });
    return candidates.first.$1;
  }

  /// Used by explicit user actions ("Take Me On A Tour"'s first segment,
  /// "Tell Me Something") — never null. Falls back through: ignoring the
  /// recently-discussed filter (repeat rather than go silent), then
  /// finally [TourSubject.general] (spec §8 tier "general", §10's "do not
  /// produce an error").
  TourSubject rankOnDemand({
    required double lat,
    required double lng,
    required List<ForestLocation> locations,
    required List<ForestTrail> trails,
    required Set<String> recentlyDiscussedIds,
    TourType tourType = TourType.general,
  }) {
    final best = rank(
      lat: lat,
      lng: lng,
      locations: locations,
      trails: trails,
      recentlyDiscussedIds: recentlyDiscussedIds,
      tourType: tourType,
    );
    if (best != null) return best;

    final ignoringHistory = rank(
      lat: lat,
      lng: lng,
      locations: locations,
      trails: trails,
      recentlyDiscussedIds: const {},
      tourType: tourType,
    );
    if (ignoringHistory != null) return ignoringHistory;

    return TourSubject.general;
  }

  Iterable<ForestLocation> _eligibleLocations(List<ForestLocation> locations, TourType tourType) sync* {
    for (final l in locations) {
      if (!l.active) continue;
      if (!tourType.matches(l.category, TourStoryType.fromStoryCategory(l.storyCategory))) continue;
      yield l;
    }
  }
}
