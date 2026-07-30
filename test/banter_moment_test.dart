import 'package:explorer_os_mobile/features/dj/banter_studio/banter_moment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('time of day / season', () {
    test('hour → time of day', () {
      expect(BanterTimeOfDay.fromHour(7), BanterTimeOfDay.morning);
      expect(BanterTimeOfDay.fromHour(14), BanterTimeOfDay.afternoon);
      expect(BanterTimeOfDay.fromHour(19), BanterTimeOfDay.evening);
      expect(BanterTimeOfDay.fromHour(2), BanterTimeOfDay.night);
    });
    test('month → season', () {
      expect(BanterSeason.fromMonth(1), BanterSeason.winter);
      expect(BanterSeason.fromMonth(4), BanterSeason.spring);
      expect(BanterSeason.fromMonth(7), BanterSeason.summer);
      expect(BanterSeason.fromMonth(10), BanterSeason.fall);
    });
  });

  group('weatherTagsFor', () {
    test('maps phrases + temp to tags', () {
      expect(weatherTagsFor('sunny skies'), contains('sunny'));
      expect(weatherTagsFor('periods of rain'), contains('rain'));
      expect(weatherTagsFor('thunderstorms'), contains('storm'));
      expect(weatherTagsFor('clear', tempF: 92), containsAll(['sunny', 'hot']));
      expect(weatherTagsFor('overcast', tempF: 40), containsAll(['cloudy', 'cold']));
    });
  });

  group('clipMatchesMoment', () {
    final morningSummerSunny = BanterMoment(
      timeOfDay: BanterTimeOfDay.morning,
      season: BanterSeason.summer,
      weather: {'sunny'},
    );

    test('untagged clip is universal', () {
      expect(clipMatchesMoment(const [], morningSummerSunny), isTrue);
      expect(clipMatchesMoment(const ['county:marion'], morningSummerSunny),
          isTrue);
    });

    test('tagged clip must match the moment dimension', () {
      expect(clipMatchesMoment(['morning'], morningSummerSunny), isTrue);
      expect(clipMatchesMoment(['evening'], morningSummerSunny), isFalse);
      expect(clipMatchesMoment(['summer', 'sunny'], morningSummerSunny), isTrue);
      expect(clipMatchesMoment(['rain'], morningSummerSunny), isFalse);
    });

    test('unknown weather does not exclude weather-tagged clips', () {
      const noWeather = BanterMoment(
        timeOfDay: BanterTimeOfDay.morning,
        season: BanterSeason.summer,
      );
      expect(clipMatchesMoment(['rain'], noWeather), isTrue);
      // But time-of-day still filters.
      expect(clipMatchesMoment(['night'], noWeather), isFalse);
    });
  });
}
