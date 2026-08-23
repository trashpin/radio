import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_story_type.dart';

/// The different tour "flavors" spec §14 asks for. Only [general] is wired
/// into any UI in this phase ("Do not build every tour type now") — the
/// rest exist so a future tour-type picker can be added without touching
/// the engine, just by exposing these already-defined filters.
enum TourType {
  general('general', '🌲 General Forest Tour'),
  hiking('hiking', '🥾 Hiking Tour'),
  birding('birding', '🐦 Birding Tour'),
  wildlife('wildlife', '🐾 Wildlife Tour'),
  springsWater('springs_water', '💧 Springs & Water Tour'),
  history('history', '📜 History Tour'),
  folklore('folklore', '🌙 Folklore Tour'),
  adventure('adventure', '🏍️ Adventure Tour');

  const TourType(this.id, this.label);
  final String id;
  final String label;

  /// Whether a [ForestLocation.category]/[storyType] pair is a fit for
  /// this tour type. [general] accepts everything; every other type is a
  /// coarse keyword/classification filter over the SAME existing
  /// `forest_locations.category` free-text field (no schema change, no new
  /// taxonomy) — good enough to route content sensibly without pretending
  /// to be a precise classifier.
  bool matches(String category, TourStoryType storyType) {
    if (this == TourType.general) return true;
    final c = category.toLowerCase();
    switch (this) {
      case TourType.general:
        return true;
      case TourType.hiking:
        return c.contains('trail') ||
            storyType == TourStoryType.nature ||
            storyType == TourStoryType.wildlife;
      case TourType.birding:
        return c.contains('bird');
      case TourType.wildlife:
        return c.contains('wildlife') ||
            c.contains('animal') ||
            storyType == TourStoryType.wildlife;
      case TourType.springsWater:
        return c.contains('spring') ||
            c.contains('lake') ||
            c.contains('river') ||
            c.contains('water') ||
            storyType == TourStoryType.geology;
      case TourType.history:
        return storyType == TourStoryType.verifiedHistory || c.contains('historic');
      case TourType.folklore:
        return storyType.isUnverified;
      case TourType.adventure:
        return c.contains('ohv') || c.contains('motor') || c.contains('road');
    }
  }
}
