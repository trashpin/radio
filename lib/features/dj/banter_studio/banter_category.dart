/// The 19 DJ Banter Studio categories. Each destination keeps a library of many
/// unique clips per category (target 20–50) so transitions rarely repeat.
///
/// Some categories are "teases" that naturally hand off into a narration
/// ([transition]); others transition into songs, station IDs, or nothing.
enum BanterCategory {
  welcome,
  arrival,
  historyTease,
  wildlifeTease,
  plantTease,
  birdTease,
  geologyTease,
  interestingFact,
  scenicObservation,
  photoOpportunity,
  trailSuggestion,
  songIntro,
  songOutro,
  stationId,
  promotion,
  departure,
  hiddenGem,
  safetyReminder,
  familyActivity;

  /// snake_case token stored in the `category` column.
  String get id {
    switch (this) {
      case BanterCategory.historyTease:
        return 'history_tease';
      case BanterCategory.wildlifeTease:
        return 'wildlife_tease';
      case BanterCategory.plantTease:
        return 'plant_tease';
      case BanterCategory.birdTease:
        return 'bird_tease';
      case BanterCategory.geologyTease:
        return 'geology_tease';
      case BanterCategory.interestingFact:
        return 'interesting_fact';
      case BanterCategory.scenicObservation:
        return 'scenic_observation';
      case BanterCategory.photoOpportunity:
        return 'photo_opportunity';
      case BanterCategory.trailSuggestion:
        return 'trail_suggestion';
      case BanterCategory.songIntro:
        return 'song_intro';
      case BanterCategory.songOutro:
        return 'song_outro';
      case BanterCategory.stationId:
        return 'station_id';
      case BanterCategory.safetyReminder:
        return 'safety_reminder';
      case BanterCategory.familyActivity:
        return 'family_activity';
      case BanterCategory.hiddenGem:
        return 'hidden_gem';
      default:
        return name; // welcome, arrival, promotion, departure, …
    }
  }

  String get label {
    switch (this) {
      case BanterCategory.welcome:
        return 'Welcome';
      case BanterCategory.arrival:
        return 'Arrival';
      case BanterCategory.historyTease:
        return 'History Tease';
      case BanterCategory.wildlifeTease:
        return 'Wildlife Tease';
      case BanterCategory.plantTease:
        return 'Plant Tease';
      case BanterCategory.birdTease:
        return 'Bird Tease';
      case BanterCategory.geologyTease:
        return 'Geology Tease';
      case BanterCategory.interestingFact:
        return 'Interesting Fact';
      case BanterCategory.scenicObservation:
        return 'Scenic Observation';
      case BanterCategory.photoOpportunity:
        return 'Photo Opportunity';
      case BanterCategory.trailSuggestion:
        return 'Trail Suggestion';
      case BanterCategory.songIntro:
        return 'Song Intro';
      case BanterCategory.songOutro:
        return 'Song Outro';
      case BanterCategory.stationId:
        return 'Station ID';
      case BanterCategory.promotion:
        return 'Promotion';
      case BanterCategory.departure:
        return 'Departure';
      case BanterCategory.hiddenGem:
        return 'Hidden Gem';
      case BanterCategory.safetyReminder:
        return 'Safety Reminder';
      case BanterCategory.familyActivity:
        return 'Family Activity';
    }
  }

  /// What this banter naturally transitions into after it plays.
  BanterTransition get transition {
    switch (this) {
      case BanterCategory.historyTease:
        return BanterTransition.historyNarration;
      case BanterCategory.wildlifeTease:
        return BanterTransition.wildlifeNarration;
      case BanterCategory.birdTease:
        return BanterTransition.wildlifeNarration;
      case BanterCategory.plantTease:
        return BanterTransition.plantNarration;
      case BanterCategory.geologyTease:
        return BanterTransition.story;
      case BanterCategory.interestingFact:
        return BanterTransition.interestingFact;
      case BanterCategory.songIntro:
      case BanterCategory.songOutro:
        return BanterTransition.song;
      case BanterCategory.stationId:
        return BanterTransition.stationId;
      default:
        return BanterTransition.song;
    }
  }

  static BanterCategory? fromId(String? id) {
    if (id == null) return null;
    final norm = id.trim().toLowerCase();
    for (final c in BanterCategory.values) {
      if (c.id == norm || c.name.toLowerCase() == norm) return c;
    }
    return null;
  }
}

/// What a piece of banter hands off into (so the DJ "naturally transitions").
enum BanterTransition {
  song,
  story,
  wildlifeNarration,
  historyNarration,
  plantNarration,
  interestingFact,
  stationId,
}

/// Lifecycle of a banter clip (mirrors the narration workflow: authored →
/// approved → voiced/published).
enum BanterStatus {
  draft,
  approved,
  published,
  archived;

  String get id => name;

  static BanterStatus fromId(String? id) {
    switch ((id ?? '').trim().toLowerCase()) {
      case 'approved':
        return BanterStatus.approved;
      case 'published':
        return BanterStatus.published;
      case 'archived':
        return BanterStatus.archived;
      default:
        return BanterStatus.draft;
    }
  }
}
