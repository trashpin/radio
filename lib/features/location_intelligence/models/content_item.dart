/// The category of a location-anchored content item. Ordered loosely by the
/// programming flow (area intro → arrival → in-park discovery). `music`, `dj`,
/// `interestingFact`, and `stationId` are non-location fillers.
enum ContentCategory {
  welcome,
  countyHistory,
  cityIntro,
  water, // river / lake / spring
  historicLandmark,
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
      case ContentCategory.countyHistory:
        return 'county_history';
      case ContentCategory.cityIntro:
        return 'city_intro';
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
    if (n.contains('spring') || n.contains('river') || n.contains('lake') ||
        n.contains('water')) {
      return ContentCategory.water;
    }
    if (n.contains('trail')) return ContentCategory.trails;
    if (n.contains('overlook') || n.contains('scenic') || n.contains('vista')) {
      return ContentCategory.scenicOverlook;
    }
    if (n.contains('hidden') || n.contains('gem')) return ContentCategory.hiddenGem;
    if (n.contains('histor') || n.contains('fort') || n.contains('heritage')) {
      return ContentCategory.history;
    }
    if (n.contains('museum')) return ContentCategory.museum;
    if (n.contains('restaurant') || n.contains('food') || n.contains('dining')) {
      return ContentCategory.restaurant;
    }
    if (n.contains('camp') || n.contains('forest') || n.contains('park')) {
      return ContentCategory.park;
    }
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
      );
}
