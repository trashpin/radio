import 'package:explorer_os_mobile/features/weather/weather_service.dart';

/// Editable county personalities (defaults; admin overrides merge on top).
const kDefaultCountyGreetings = <String, String>{
  'marion': 'Welcome to Marion County, the Horse Capital of the World.',
  'alachua': 'Welcome to beautiful Alachua County.',
  'citrus': 'Welcome to Citrus County, home of Crystal River and the manatees.',
  'lake': 'Welcome to scenic Lake County.',
  'levy': 'Welcome to Levy County.',
  'sumter': 'Welcome to Sumter County.',
  'putnam': 'Welcome to Putnam County, along the historic St. Johns River.',
  'volusia': 'Welcome to Volusia County.',
};

String greetingFor(
  String? county,
  String? state, [
  Map<String, String> overrides = const {},
]) {
  final key = (county ?? '').toLowerCase().trim();
  if (key.isEmpty) {
    return state == null || state.trim().isEmpty
        ? 'Welcome, traveler, to Sunshine Travel Radio.'
        : 'Welcome to $state.';
  }
  final custom = overrides[key] ?? kDefaultCountyGreetings[key];
  if (custom != null) return custom;
  final st = (state ?? '').trim();
  return 'Welcome to $county County${st.isNotEmpty ? ', $st' : ''}.';
}

/// Weather-aware recommendation pools (rotated so it's never the same twice).
const _recSunny = [
  'A perfect day to visit one of our beautiful springs.',
  "It's a fantastic day for a scenic drive.",
  'Great weather to explore a state park or paddle a clear spring run.',
];
const _recCool = [
  'Excellent weather for hiking one of the local trails.',
  'A crisp, comfortable day to explore the outdoors.',
];
const _recRain = [
  'You may want to plan for indoor attractions later this afternoon.',
  'A good afternoon for a museum or a cozy local cafe.',
];
const _recWindy = [
  'Boaters should be aware of gusty conditions on the water today.',
  'Hold onto your hat — it may be breezy out there.',
];
const _recDefault = [
  'A wonderful day to discover something new nearby.',
  'Keep exploring — there is always something to see around here.',
];

List<String> recommendationPool(WeatherData? w) {
  if (w == null) return _recDefault;
  if (w.rainLikely) return _recRain;
  if (w.windy) return _recWindy;
  if (w.coolMorning) return _recCool;
  if (w.sunny) return _recSunny;
  return _recDefault;
}

/// Picks a recommendation, rotating through the pool by [rotation].
String pickRecommendation(WeatherData? w, int rotation) {
  final pool = recommendationPool(w);
  return pool[rotation.abs() % pool.length];
}

/// Builds the county welcome radio sequence and enforces once-per-county.
class CountyWelcomeDirector {
  CountyWelcomeDirector({
    this.stationId = "You're listening to Sunshine Travel Radio.",
  });

  final String stationId;
  final Set<String> _welcomed = <String>{};
  int _recRotation = 0;

  bool hasWelcomed(String? county) =>
      _welcomed.contains((county ?? '').toLowerCase().trim());

  /// Returns the spoken script for entering [county], or null if the county is
  /// unknown or was already welcomed this trip. Sequence: Station ID → County
  /// Welcome → Weather → one rotating Recommendation.
  String? scriptFor(
    String? county,
    String? state,
    WeatherData? weather, {
    Map<String, String> greetings = const {},
    bool weatherEnabled = true,
    bool recommendationsEnabled = true,
  }) {
    final key = (county ?? '').toLowerCase().trim();
    if (key.isEmpty || _welcomed.contains(key)) return null;
    _welcomed.add(key);

    final lines = <String>[stationId, greetingFor(county, state, greetings)];
    if (weatherEnabled && weather != null) {
      lines.add(summarizeWeather(weather));
    }
    if (recommendationsEnabled) {
      lines.add(pickRecommendation(weather, _recRotation));
      _recRotation++;
    }
    return lines.join(' ');
  }

  /// Marks that the traveler has LEFT [county], so entering it again later in
  /// the same trip plays the welcome once more ("only once until you leave the
  /// county"). Called on a county transition with the previous county.
  void leftCounty(String? county) {
    final key = (county ?? '').toLowerCase().trim();
    if (key.isEmpty) return;
    _welcomed.remove(key);
  }

  /// Clears welcomed history (e.g. new trip). County change itself is handled
  /// by [scriptFor] returning null for the same county.
  void reset() {
    _welcomed.clear();
  }
}
