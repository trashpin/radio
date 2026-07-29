/// Editable per-county radio personality (Admin → County Manager).
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
  });

  final String id;
  final String name; // county name, e.g. "Marion"
  final String state;
  final String? welcome; // custom greeting line
  final String? description;
  final String? themeSongUrl;
  final String? weatherVoice;
  final bool weatherEnabled;
  final bool recommendationsEnabled;
  final List<String> recommendations;

  String get key => name.toLowerCase().trim();

  static List<String> _strs(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

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
      };
}
