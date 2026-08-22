import 'dart:math';

import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_experience_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';

/// Chooses which Forest Story to play near the traveler's current position.
///
/// Mirrors `GpsStorySelector` (`lib/features/story_studio/services/gps_story_selector.dart`)
/// exactly — same rules (only in-range stories, avoid repeats this visit
/// unless that leaves nothing, pick randomly among what's eligible) — but
/// operates on [ForestLocation] (`experienceType == 'story'`) instead of
/// the Marion-specific `StoryEntry`, since the two live in unrelated,
/// deliberately isolated tables.
class ForestStorySelector {
  ForestStorySelector({Random? rng}) : _rng = rng ?? Random();
  final Random _rng;

  List<ForestLocation> inRange(
    List<ForestLocation> locations,
    double lat,
    double lng, {
    String? storyCategory,
  }) {
    return locations.where((l) {
      if (!l.isStory || !l.active) return false;
      if (storyCategory != null && l.storyCategory != storyCategory) return false;
      final radius = l.geofenceRadiusMeters ?? kForestDefaultGeofenceMeters;
      final d = GeoMath.distanceMeters(lat, lng, l.latitude, l.longitude);
      return d <= radius;
    }).toList();
  }

  ForestLocation? select(
    List<ForestLocation> locations,
    double lat,
    double lng, {
    Set<String> alreadyPlayed = const {},
    String? storyCategory,
  }) {
    final eligible = inRange(locations, lat, lng, storyCategory: storyCategory);
    if (eligible.isEmpty) return null;
    final fresh = eligible.where((l) => !alreadyPlayed.contains(l.id)).toList();
    final pool = fresh.isNotEmpty ? fresh : eligible;
    return pool[_rng.nextInt(pool.length)];
  }
}
