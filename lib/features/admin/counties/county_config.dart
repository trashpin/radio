/// Editable per-county radio personality + County Profile (Admin → County
/// Manager). The radio-personality fields (welcome/description/theme song/
/// weather/recommendations) predate the County Profile fields added below —
/// kept together since they're the same admin-editable row.
class CountyConfig {
  const CountyConfig({
    required this.id,
    required this.name,
    this.state = 'Florida',
    this.welcome,
    this.description,
    this.themeSongUrl,
    this.weatherVoice,
    this.weatherEnabled = true,
    this.recommendationsEnabled = true,
    this.recommendations = const [],
    this.sealUrl,
    this.heroImageUrl,
    this.welcomeNarrationUrl,
    this.history,
    this.overview,
    this.population,
    this.sizeSqMiles,
    this.yearEstablished,
    this.facts = const [],
    this.tourismInfo,
    this.officialWebsite,
    this.galleryImages = const [],
  });

  final String id;
  final String name; // county name, e.g. "Marion"
  final String state;
  final String? welcome; // custom greeting line (spoken script)
  final String? description;
  final String? themeSongUrl;
  final String? weatherVoice;
  final bool weatherEnabled;
  final bool recommendationsEnabled;
  final List<String> recommendations;

  // County Profile.
  final String? sealUrl;
  final String? heroImageUrl;

  /// Generated audio for [welcome] (the script) — same script/audio pairing
  /// used elsewhere (e.g. nearby_gems narration_script/narration_url).
  final String? welcomeNarrationUrl;
  final String? history;
  final String? overview;
  final int? population;
  final double? sizeSqMiles;
  final int? yearEstablished;
  final List<String> facts;
  final String? tourismInfo;
  final String? officialWebsite;
  final List<String> galleryImages;

  String get key => name.toLowerCase().trim();

  static List<String> _strs(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];
  static int? _i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  static double? _d(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  factory CountyConfig.fromJson(Map<String, dynamic> j) => CountyConfig(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '') as String,
        state: (j['state'] ?? 'Florida') as String,
        welcome: j['welcome'] as String?,
        description: j['description'] as String?,
        themeSongUrl: j['theme_song_url'] as String?,
        weatherVoice: j['weather_voice'] as String?,
        weatherEnabled: (j['weather_enabled'] ?? true) as bool,
        recommendationsEnabled: (j['recommendations_enabled'] ?? true) as bool,
        recommendations: _strs(j['recommendations']),
        sealUrl: j['seal_url'] as String?,
        heroImageUrl: j['hero_image_url'] as String?,
        welcomeNarrationUrl: j['welcome_narration_url'] as String?,
        history: j['history'] as String?,
        overview: j['overview'] as String?,
        population: _i(j['population']),
        sizeSqMiles: _d(j['size_sq_miles']),
        yearEstablished: _i(j['year_established']),
        facts: _strs(j['facts']),
        tourismInfo: j['tourism_info'] as String?,
        officialWebsite: j['official_website'] as String?,
        galleryImages: _strs(j['gallery_images']),
      );

  Map<String, dynamic> toWrite() => {
        'name': name,
        'state': state,
        'welcome': welcome,
        'description': description,
        'theme_song_url': themeSongUrl,
        'weather_voice': weatherVoice,
        'weather_enabled': weatherEnabled,
        'recommendations_enabled': recommendationsEnabled,
        'recommendations': recommendations,
        'seal_url': sealUrl,
        'hero_image_url': heroImageUrl,
        'welcome_narration_url': welcomeNarrationUrl,
        'history': history,
        'overview': overview,
        'population': population,
        'size_sq_miles': sizeSqMiles,
        'year_established': yearEstablished,
        'facts': facts,
        'tourism_info': tourismInfo,
        'official_website': officialWebsite,
        'gallery_images': galleryImages,
      };

  /// Fraction (0..1) of County Profile fields that are filled in — for a
  /// future County Completion Dashboard. Radio-personality fields
  /// (welcome/theme song/etc.) aren't counted here; this is specifically the
  /// "County Profile" checklist from the content spec.
  double get profileCompleteness {
    final checks = <bool>[
      (sealUrl ?? '').trim().isNotEmpty,
      (heroImageUrl ?? '').trim().isNotEmpty,
      (welcomeNarrationUrl ?? '').trim().isNotEmpty,
      (history ?? '').trim().isNotEmpty,
      (overview ?? '').trim().isNotEmpty,
      population != null,
      sizeSqMiles != null,
      yearEstablished != null,
      facts.isNotEmpty,
      (tourismInfo ?? '').trim().isNotEmpty,
      (officialWebsite ?? '').trim().isNotEmpty,
      galleryImages.isNotEmpty,
    ];
    return checks.where((b) => b).length / checks.length;
  }
}
