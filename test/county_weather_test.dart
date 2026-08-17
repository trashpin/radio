import 'package:explorer_os_mobile/features/weather/county_radio.dart';
import 'package:explorer_os_mobile/features/weather/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('weather', () {
    test('WMO codes map to phrases', () {
      expect(weatherPhraseForCode(0), 'sunny skies');
      expect(weatherPhraseForCode(3), 'overcast skies');
      expect(weatherPhraseForCode(95), 'thunderstorms');
    });

    test('summarizeWeather is conversational, no raw dump', () {
      final s = summarizeWeather(const WeatherData(
          highF: 91, condition: 'sunny skies', rainChance: 30));
      expect(s, contains('high near 91 degrees'));
      expect(s, contains('sunny skies'));
      expect(s, contains('slight chance'));
      expect(s.endsWith('.'), isTrue);
    });

    test('parseOpenMeteo pulls current + daily', () {
      final w = parseOpenMeteo({
        'current': {
          'temperature_2m': 84.2,
          'relative_humidity_2m': 55,
          'wind_speed_10m': 6.0,
          'weather_code': 0,
        },
        'daily': {
          'temperature_2m_max': [90.5],
          'temperature_2m_min': [70.1],
          'precipitation_probability_max': [20],
          'weather_code': [0],
        },
      });
      expect(w.highF, 90.5);
      expect(w.condition, 'sunny skies');
      expect(w.rainChance, 20);
      expect(w.sunny, isTrue);
    });
  });

  group('county greetings', () {
    test('uses custom personality, then override, then generic', () {
      expect(greetingFor('Marion', 'Florida'),
          'Welcome to Marion County, the Horse Capital of the World.');
      expect(greetingFor('Nowhere', 'Florida'),
          'Welcome to Nowhere County, Florida.');
      expect(greetingFor('Marion', 'Florida', {'marion': 'Hi Marion!'}),
          'Hi Marion!');
    });
  });

  group('recommendations rotate + match weather', () {
    test('rain → indoor rec, sunny → springs rec', () {
      expect(pickRecommendation(const WeatherData(rainChance: 80), 0),
          contains('indoor'));
      expect(pickRecommendation(const WeatherData(condition: 'sunny skies'), 0),
          contains('springs'));
    });
    test('rotation advances through the pool', () {
      final w = const WeatherData(condition: 'sunny skies');
      final a = pickRecommendation(w, 0);
      final b = pickRecommendation(w, 1);
      expect(a, isNot(b));
    });
    test('county recommendations blend into the weather pool', () {
      // No weather → _recDefault (2 entries); one blended custom → index 2.
      expect(
        pickRecommendation(null, 2, extra: const ['Visit Silver Springs.']),
        'Visit Silver Springs.',
      );
      // Blank custom entries are ignored (don't pollute the pool).
      expect(
        pickRecommendation(null, 0, extra: const ['  ', '']),
        isNot('  '),
      );
    });
  });

  group('CountyWelcomeDirector', () {
    test('welcomes once per county, resets on new county', () {
      final d = CountyWelcomeDirector();
      final first = d.scriptFor('Marion', 'Florida',
          const WeatherData(highF: 90, condition: 'sunny skies'));
      expect(first, isNotNull);
      expect(first, contains("You're listening to ExplorerOS Radio"));
      expect(first, contains('Marion County'));
      expect(first, contains('90 degrees'));
      // Same county again → no repeat.
      expect(d.scriptFor('Marion', 'Florida', null), isNull);
      // New county → welcomes.
      expect(d.scriptFor('Alachua', 'Florida', null), isNotNull);
    });

    test('unknown county returns null', () {
      expect(CountyWelcomeDirector().scriptFor(null, 'Florida', null), isNull);
      expect(CountyWelcomeDirector().scriptFor('  ', null, null), isNull);
    });

    test('weather disabled omits the forecast line', () {
      final d = CountyWelcomeDirector();
      final s = d.scriptFor('Levy', 'Florida',
          const WeatherData(highF: 88, condition: 'sunny skies'),
          weatherEnabled: false);
      expect(s, isNot(contains('high near')));
    });

    test('both toggles off → just station ID + greeting (recs list ignored)',
        () {
      final d = CountyWelcomeDirector();
      final s = d.scriptFor(
        'Sumter',
        'Florida',
        const WeatherData(highF: 80, condition: 'sunny skies'),
        weatherEnabled: false,
        recommendationsEnabled: false,
        recommendations: const ['Visit Silver Springs.'],
      );
      expect(
          s, "You're listening to ExplorerOS Radio. Welcome to Sumter County.");
      expect(s, isNot(contains('Silver Springs')));
    });
  });
}
