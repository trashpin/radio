/// The category of a location-anchored content item. Ordered loosely by the
/// programming flow (area intro → arrival → in-park discovery). `music`, `dj`,
/// `interestingFact`, and `stationId` are non-location fillers.
enum ContentCategory {
  welcome,
  // County layer.
  countyWelcome,
  countyHistory,
  countyFunFacts,
  countyNature,
  countyAgriculture,
  countyEconomy,
  countyHiddenGems,
  // City / community layer.
  cityWelcome,
  cityHistory,
  cityFunFacts,
  cityIntro,
  communityStory,
  // Natural + travel-corridor layer.
  water, // generic river / lake / spring
  riverStory,
  lakeStory,
  forestStory,
  historicHighway,
  scenicDrive,
  historicLandmark,
  // Park layer (now just one layer of the experience).
  park, // state park / national forest
  arrival,
  parkStory,
  wildlife,
  plants,
  birds,
  trees,
  trails,
  scenicOverlook,
  hiddenGem,
  history,
  attraction,
  restaurant,
  museum,
  scenicRoad,
  departure,
  interestingFact,
  music,
  dj,
  stationId;

  String get id {
    switch (this) {
      case ContentCategory.countyWelcome:
        return 'county_welcome';
      case ContentCategory.countyHistory:
        return 'county_history';
      case ContentCategory.countyFunFacts:
        return 'county_fun_facts';
      case ContentCategory.countyNature:
        return 'county_nature';
      case ContentCategory.countyAgriculture:
        return 'county_agriculture';
      case ContentCategory.countyEconomy:
        return 'county_economy';
      case ContentCategory.countyHiddenGems:
        return 'county_hidden_gems';
      case ContentCategory.cityWelcome:
        return 'city_welcome';
      case ContentCategory.cityHistory:
        return 'city_history';
      case ContentCategory.cityFunFacts:
        return 'city_fun_facts';
      case ContentCategory.cityIntro:
        return 'city_intro';
      case ContentCategory.communityStory:
        return 'community_story';
      case ContentCategory.riverStory:
        return 'river_story';
      case ContentCategory.lakeStory:
        return 'lake_story';
      case ContentCategory.forestStory:
        return 'forest_story';
      case ContentCategory.historicHighway:
        return 'historic_highway';
      case ContentCategory.scenicDrive:
        return 'scenic_drive';
      case ContentCategory.historicLandmark:
        return 'historic_landmark';
      case ContentCategory.parkStory:
        return 'park_story';
      case ContentCategory.scenicOverlook:
        return 'scenic_overlook';
      case ContentCategory.hiddenGem:
        return 'hidden_gem';
      case ContentCategory.scenicRoad:
        return 'scenic_road';
      case ContentCategory.interestingFact:
        return 'interesting_fact';
      case ContentCategory.stationId:
        return 'station_id';
      default:
        return name;
    }
  }

  bool get isMusic => this == ContentCategory.music;

  static ContentCategory fromId(String? raw) {
    if (raw == null) return ContentCategory.history;
    final n = raw.trim().toLowerCase();
    for (final c in ContentCategory.values) {
      if (c.id == n || c.name.toLowerCase() == n) return c;
    }
    // Loose keyword mapping for free-form source categories.
    if (n.contains('bird')) return ContentCategory.birds;
    if (n.contains('tree')) return ContentCategory.trees;
    if (n.contains('plant') || n.contains('flora') || n.contains('wildflower')) {
      return ContentCategory.plants;
    }
    if (n.contains('wildlife') || n.contains('animal') || n.contains('mammal')) {
      return ContentCategory.wildlife;
    }
    if (n.contains('river') || n.contains('creek')) {
      return ContentCategory.riverStory;
    }
    if (n.contains('lake')) return ContentCategory.lakeStory;
    if (n.contains('spring') || n.contains('water')) return ContentCategory.water;
    if (n.contains('trail')) return ContentCategory.trails;
    if (n.contains('scenic') && (n.contains('drive') || n.contains('road') ||
        n.contains('highway') || n.contains('byway'))) {
      return ContentCategory.scenicDrive;
    }
    if (n.contains('overlook') || n.contains('scenic') || n.contains('vista')) {
      return ContentCategory.scenicOverlook;
    }
    if (n.contains('community') || n.contains('unincorporated')) {
      return ContentCategory.communityStory;
    }
    if (n.contains('hidden') || n.contains('gem')) return ContentCategory.hiddenGem;
    if (n.contains('histor') || n.contains('fort') || n.contains('heritage')) {
      return ContentCategory.history;
    }
    if (n.contains('museum')) return ContentCategory.museum;
    if (n.contains('restaurant') || n.contains('food') || n.contains('dining')) {
      return ContentCategory.restaurant;
    }
    if (n.contains('forest')) return ContentCategory.forestStory;
    if (n.contains('camp') || n.contains('park')) return ContentCategory.park;
    return ContentCategory.attraction;
  }
}

/// A single geocoded, location-anchored content item — the atom the Location
/// Intelligence Engine reasons about. Mirrors the `location_content` table.
class ContentItem {
  const ContentItem({
    required this.id,
    required this.title,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.subcategory,
    this.county,
    this.city,
    this.state,
    this.park,
    this.radiusMeters,
    this.basePriority = 0,
    this.estimatedDuration = const Duration(minutes: 2),
    this.cooldown = const Duration(hours: 6),
    this.playCount = 0,
    this.lastPlayed,
    this.audioUrl,
    this.text,
    this.ambientType,
  });

  final String id;
  final String title;
  final ContentCategory category;
  final String? subcategory;
  final double latitude;
  final double longitude;
  final String? county;
  final String? city;
  final String? state;
  final String? park;

  /// Optional relevance radius (meters). When set, the item is only eligible
  /// when the visitor is within it.
  final double? radiusMeters;

  /// Author-set base priority bump (added on top of the distance score).
  final int basePriority;
  final Duration estimatedDuration;
  final Duration cooldown;
  final int playCount;
  final DateTime? lastPlayed;
  final String? audioUrl;
  final String? text;

  /// Optional ambient-sound TYPE (e.g. `flowing_water`, `birds`) this piece's
  /// narration may play underneath, admin-authored per content record —
  /// resolved to a playable clip against the `ambient_sounds` library by the
  /// Explore candidate builder. Null/`none` means no ambient association.
  final String? ambientType;

  bool get hasCoordinates => latitude != 0 || longitude != 0;

  static double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
  static Duration _dur(dynamic v, Duration fallback) {
    final n = v is num ? v.toInt() : int.tryParse('$v');
    return n == null ? fallback : Duration(seconds: n);
  }

  factory ContentItem.fromJson(Map<String, dynamic> j) => ContentItem(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? j['name'] ?? '') as String,
        category: ContentCategory.fromId(j['category'] as String?),
        subcategory: j['subcategory'] as String?,
        latitude: _d(j['latitude']) ?? 0,
        longitude: _d(j['longitude']) ?? 0,
        county: j['county'] as String?,
        city: j['city'] as String?,
        state: j['state'] as String?,
        park: j['park'] as String?,
        radiusMeters: _d(j['radius']),
        basePriority: (j['priority'] as num?)?.toInt() ?? 0,
        estimatedDuration: _dur(j['estimated_duration'], const Duration(minutes: 2)),
        cooldown: _dur(j['cooldown'], const Duration(hours: 6)),
        playCount: (j['play_count'] as num?)?.toInt() ?? 0,
        lastPlayed: DateTime.tryParse('${j['last_played']}'),
        audioUrl: j['audio_url'] as String?,
        text: j['text'] as String?,
        ambientType: j['ambient_type'] as String?,
      );

  ContentItem copyWith({int? playCount, DateTime? lastPlayed}) => ContentItem(
        id: id,
        title: title,
        category: category,
        subcategory: subcategory,
        latitude: latitude,
        longitude: longitude,
        county: county,
        city: city,
        state: state,
        park: park,
        radiusMeters: radiusMeters,
        basePriority: basePriority,
        estimatedDuration: estimatedDuration,
        cooldown: cooldown,
        playCount: playCount ?? this.playCount,
        lastPlayed: lastPlayed ?? this.lastPlayed,
        audioUrl: audioUrl,
        text: text,
        ambientType: ambientType,
      );
}
