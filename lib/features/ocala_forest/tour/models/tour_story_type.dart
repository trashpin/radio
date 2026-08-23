/// The tour's content-classification taxonomy (spec §12) — kept
/// deliberately DATA-DRIVEN: this is derived from what's already in
/// `ForestLocation.storyCategory`/`ForestTrail`'s own fields, never
/// something OpenAI decides for itself. The narration prompt is told which
/// classification a subject has and instructed to phrase it accordingly
/// (verified fact vs. "local folklore says…") — the classification itself
/// always comes from the data, so the AI can never quietly upgrade folklore
/// into established fact.
enum TourStoryType {
  verifiedHistory('verified_history', 'Verified History'),
  nature('nature', 'Nature'),
  wildlife('wildlife', 'Wildlife'),
  geology('geology', 'Geology'),
  localStory('local_story', 'Local Story'),
  folklore('folklore', 'Folklore'),
  legend('legend', 'Legend'),
  unverified('unverified', 'Unverified'),

  /// No specific subject — a general Ocala National Forest segment (spec
  /// §8 TEST 8: "no nearby specific content" must never be an error).
  general('general', 'General');

  const TourStoryType(this.id, this.label);
  final String id;
  final String label;

  /// True for anything that must be spoken as a caveated, non-factual
  /// claim rather than settled information.
  bool get isUnverified =>
      this == TourStoryType.folklore ||
      this == TourStoryType.legend ||
      this == TourStoryType.unverified;

  /// Maps a [ForestLocation.storyCategory] value (free text, e.g.
  /// 'WILDLIFE'/'HISTORY' per the existing v2 seed-data convention) to a
  /// [TourStoryType]. Unknown/absent values default to [localStory] — a
  /// safe middle ground that still gets spoken as "we found this
  /// interesting" rather than being silently promoted to verified history.
  static TourStoryType fromStoryCategory(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    switch (v) {
      case 'history':
      case 'verified_history':
        return TourStoryType.verifiedHistory;
      case 'nature':
        return TourStoryType.nature;
      case 'wildlife':
        return TourStoryType.wildlife;
      case 'geology':
        return TourStoryType.geology;
      case 'folklore':
        return TourStoryType.folklore;
      case 'legend':
        return TourStoryType.legend;
      case 'unverified':
        return TourStoryType.unverified;
      case '':
        return TourStoryType.localStory;
      default:
        return TourStoryType.localStory;
    }
  }
}
