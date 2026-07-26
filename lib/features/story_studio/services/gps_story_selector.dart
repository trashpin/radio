import 'dart:math';

import 'package:explorer_os_mobile/features/story_studio/models/story_category.dart';
import 'package:explorer_os_mobile/features/story_studio/models/story_entry.dart';

/// Chooses which story to play when a visitor is at a location.
///
/// PURE: given the published stories, the user's position, and which stories
/// were already played this visit, it returns the story to play (or null).
/// Rules: only playable (published + audio + coords) stories within their
/// trigger radius; filter by park/category if requested; avoid repeats this
/// visit unless that leaves nothing; pick randomly among the eligible.
class GpsStorySelector {
  GpsStorySelector({Random? rng}) : _rng = rng ?? Random();
  final Random _rng;

  /// Stories whose trigger zone currently contains the user.
  List<StoryEntry> inRange(
    List<StoryEntry> stories,
    double lat,
    double lng, {
    String? parkId,
    StoryCategory? category,
  }) {
    return stories.where((s) {
      if (!s.playable) return false;
      if (parkId != null && s.parkId != null && s.parkId != parkId) return false;
      if (category != null && s.category != category) return false;
      final d = metersBetween(lat, lng, s.latitude!, s.longitude!);
      return d <= s.triggerRadiusM;
    }).toList();
  }

  /// Selects a story to play, avoiding [alreadyPlayed] unless nothing else is
  /// eligible. Returns null when nothing is in range.
  StoryEntry? select(
    List<StoryEntry> stories,
    double lat,
    double lng, {
    Set<String> alreadyPlayed = const {},
    String? parkId,
    StoryCategory? category,
  }) {
    final eligible =
        inRange(stories, lat, lng, parkId: parkId, category: category);
    if (eligible.isEmpty) return null;
    final fresh =
        eligible.where((s) => !alreadyPlayed.contains(s.id)).toList();
    final pool = fresh.isNotEmpty ? fresh : eligible;
    return pool[_rng.nextInt(pool.length)];
  }
}
