/// Story categories the production pipeline supports. Expandable — add a value
/// here (and it flows through the generator, library filters, and playback).
enum StoryCategory {
  parkHistory('PARK_HISTORY', 'Park History'),
  nativeAmericanHistory('NATIVE_AMERICAN_HISTORY', 'Native American History'),
  earlySettlers('EARLY_SETTLERS', 'Early Settlers'),
  ccc('CCC', 'Civilian Conservation Corps'),
  wildlife('WILDLIFE', 'Wildlife Stories'),
  plants('PLANTS', 'Plant Stories'),
  trees('TREES', 'Tree Stories'),
  wildflowers('WILDFLOWERS', 'Wildflower Stories'),
  geology('GEOLOGY', 'Geological Stories'),
  springs('SPRINGS', 'Spring Stories'),
  lakes('LAKES', 'Lake Stories'),
  rivers('RIVERS', 'River Stories'),
  scenicViewpoints('SCENIC_VIEWPOINTS', 'Scenic Viewpoints'),
  campgrounds('CAMPGROUNDS', 'Campground Stories'),
  trails('TRAILS', 'Trail Stories'),
  hiddenGems('HIDDEN_GEMS', 'Hidden Gems'),
  rangerTips('RANGER_TIPS', 'Ranger Tips'),
  safety('SAFETY', 'Safety Information'),
  conservation('CONSERVATION', 'Conservation'),
  seasonal('SEASONAL', 'Seasonal Stories'),
  nightSky('NIGHT_SKY', 'Night Sky'),
  birdMigration('BIRD_MIGRATION', 'Bird Migration'),
  funFacts('FUN_FACTS', 'Fun Facts'),
  childrens('CHILDRENS', "Children's Stories"),
  legends('LEGENDS', 'Legends'),
  folklore('FOLKLORE', 'Local Folklore');

  const StoryCategory(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static StoryCategory fromDb(String? v) => StoryCategory.values.firstWhere(
        (e) => e.dbValue == v,
        orElse: () => StoryCategory.parkHistory,
      );
}

/// A stylistic angle for a story about the same location (rotated at playback
/// to reduce repetition).
enum StoryVariation {
  historical('Historical'),
  wildlife('Wildlife Focus'),
  familyFriendly('Family Friendly'),
  photography('Photography'),
  adventure('Adventure'),
  nativePlants('Native Plants'),
  funFacts('Fun Facts');

  const StoryVariation(this.label);
  final String label;
}

/// Where a story sits in the production workflow.
enum StoryStatus {
  draft('draft', 'Draft'),
  review('review', 'Waiting for Review'),
  approved('approved', 'Approved'),
  generatingAudio('generating_audio', 'Generating Audio'),
  completed('completed', 'Completed'),
  failed('failed', 'Failed');

  const StoryStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static StoryStatus fromDb(String? v) => StoryStatus.values.firstWhere(
        (e) => e.dbValue == v,
        orElse: () => StoryStatus.draft,
      );
}

/// Target audience for a story.
enum StoryAudience {
  general('general', 'General'),
  family('family', 'Family'),
  children('children', 'Children'),
  enthusiast('enthusiast', 'Enthusiast');

  const StoryAudience(this.dbValue, this.label);
  final String dbValue;
  final String label;
}
