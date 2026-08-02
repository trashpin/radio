import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// A words-per-minute estimate used only as a fallback when a location's
/// `estimated_listening_minutes` hasn't been set explicitly — never shown as
/// more authoritative than an admin-entered value.
const _fallbackWordsPerMinute = 150;

/// The "Discover This Area" hub for one area — wraps a
/// `MasterLocation` with `type == LocationType.area` plus everything
/// computed from the traveler's current position. Deliberately a thin
/// wrapper (not a duplicate content store): every field but [distanceMeters]
/// comes straight from the existing Master Locations record.
class DiscoveryArea {
  const DiscoveryArea({required this.location, required this.distanceMeters});

  final MasterLocation location;

  /// Straight-line distance from the traveler's current position to this
  /// area's center — 0 when they're inside its trigger radius.
  final double distanceMeters;

  String get name => location.name;
  String? get heroImageUrl => location.images.isNotEmpty ? location.images.first : null;
  List<String> get gallery => location.images;
  String? get shortIntroduction =>
      (location.shortDescription?.trim().isNotEmpty ?? false)
          ? location.shortDescription
          : location.description;

  /// Whether the traveler is currently physically inside this area's
  /// trigger radius (vs. just being shown it as "nearby").
  bool get isCurrentlyInside => distanceMeters <= (location.triggerRadius ?? 0);

  /// Minutes to listen to this area's full narrated content. Uses the
  /// admin-set value when present; otherwise estimates from the narration
  /// script's word count at [_fallbackWordsPerMinute] — never blocks the
  /// screen on a missing number.
  int get estimatedListeningMinutes {
    final set = location.estimatedListeningMinutes;
    if (set != null && set > 0) return set;
    final script = location.narrationScript?.trim() ?? '';
    if (script.isEmpty) return 0;
    final words = script.split(RegExp(r'\s+')).length;
    return (words / _fallbackWordsPerMinute).ceil().clamp(1, 999);
  }
}

/// Picks the single best-matching area for [latitude]/[longitude] out of
/// every area-type location, or null if the traveler isn't inside (or near)
/// any of them.
///
/// "Best" means: prefer an area the traveler is actually inside (smallest
/// trigger radius wins ties — the more specific area, e.g. "Historic
/// Downtown Ocala" over the much larger "Ocala National Forest" that
/// happens to contain it); if inside none, fall back to the nearest area
/// within [nearbyFallbackMeters] so the feature still has something to show
/// just outside a hard boundary.
///
/// Pure — no I/O, easy to unit test independently of GPS/Supabase.
DiscoveryArea? detectCurrentArea(
  List<MasterLocation> allLocations,
  double latitude,
  double longitude, {
  double nearbyFallbackMeters = 3000,
}) {
  final areas = allLocations.where(
    (l) => l.type == LocationType.area && l.active && !l.hidden && l.hasCoordinates,
  );
  if (areas.isEmpty) return null;

  DiscoveryArea? best;
  for (final area in areas) {
    final distance = GeoMath.distanceMeters(
      latitude,
      longitude,
      area.latitude!,
      area.longitude!,
    );
    final radius = area.triggerRadius ?? 0;
    final inside = distance <= radius;
    final candidate = DiscoveryArea(location: area, distanceMeters: distance);

    if (best == null) {
      best = candidate;
      continue;
    }
    final bestInside = best.isCurrentlyInside;
    if (inside && !bestInside) {
      // Any area we're actually inside beats one we're merely near.
      best = candidate;
    } else if (inside == bestInside) {
      // Both inside (smaller/more specific radius wins) or both outside
      // (nearer one wins) — same comparison either way.
      final bestMetric = bestInside ? (best.location.triggerRadius ?? 0) : best.distanceMeters;
      final candidateMetric = inside ? radius : distance;
      if (candidateMetric < bestMetric) best = candidate;
    }
  }

  if (best == null) return null;
  if (!best.isCurrentlyInside && best.distanceMeters > nearbyFallbackMeters) {
    return null; // Nothing close enough to be worth showing.
  }
  return best;
}
