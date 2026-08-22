import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/around_me/logic/explorer_score.dart';
import 'package:explorer_os_mobile/features/around_me/models/experience.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';

/// How far out "What's Around Me" looks for forest locations — generous
/// since the forest itself spans tens of miles (unlike Marion's tighter
/// urban "around me" radius).
const double kForestAroundMeRadiusMeters = 8046.72; // 5 miles

/// The forest's own "What's Around Me" feed — reuses `Experience` (plain
/// data) and `explorerScore`/`ExplorerScoreInput` (pure ranking) UNCHANGED
/// from `lib/features/around_me/`, mapped from `ForestLocation` instead of
/// Marion's `map_locations`. Automatic arrival narration is already
/// handled feature-wide by `ForestExperienceController` — this provider is
/// purely the ranked, browsable read side (distance + proximity/featured/
/// season/time-of-day scoring), not a second geofence detector.
final forestAroundMeExperiencesProvider = Provider<List<Experience>>((ref) {
  final loc = ref.watch(gpsControllerProvider).location;
  if (loc == null) return const [];
  final locations = ref.watch(forestLocationsProvider).value ?? const [];

  final out = <Experience>[];
  for (final l in locations) {
    if (!l.active) continue;
    final dist = GeoMath.distanceMeters(
        loc.latitude, loc.longitude, l.latitude, l.longitude);
    if (dist > kForestAroundMeRadiusMeters) continue;
    final bearing = GeoMath.bearingDegrees(
        loc.latitude, loc.longitude, l.latitude, l.longitude);
    final score = explorerScore(ExplorerScoreInput(
      distanceMeters: dist,
      radiusMeters: kForestAroundMeRadiusMeters,
    ));
    out.add(Experience(
      id: l.id,
      name: l.name,
      category: l.category,
      subcategory: l.experienceType,
      description: l.description,
      imageUrl: l.imageUrl,
      audioUrl: l.hasAudio ? l.audioUrl : null,
      latitude: l.latitude,
      longitude: l.longitude,
      distanceMeters: dist,
      bearingDegrees: bearing,
      score: score,
    ));
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
});
