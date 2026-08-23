import 'dart:math';

import 'package:explorer_os_mobile/features/discover_home/models/discover_greeting_context.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discover_greeting_library.dart';
import 'package:explorer_os_mobile/features/discover_home/services/discover_greeting_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const selector = DiscoverGreetingSelector();

  group('time/day flavor', () {
    test('a morning weekday context only returns generic/morning/weekday lines', () {
      final ctx = DiscoverGreetingContext(hour: 8, weekday: DateTime.tuesday);
      const allowed = {
        GreetingFlavor.generic,
        GreetingFlavor.morning,
        GreetingFlavor.weekday,
      };
      for (var i = 0; i < 30; i++) {
        final t = selector.select(context: ctx, random: Random(i));
        expect(
          allowed.contains(t.flavor),
          isTrue,
          reason: 'unexpected flavor ${t.flavor} for a morning weekday context',
        );
      }
    });

    test('a Friday context can surface Friday-flavored lines', () {
      final ctx = DiscoverGreetingContext(hour: 18, weekday: DateTime.friday);
      final flavors = {
        for (var i = 0; i < 50; i++) selector.select(context: ctx, random: Random(i)).flavor,
      };
      expect(flavors, contains(GreetingFlavor.friday));
    });

    test('a Saturday context never surfaces plain-weekday lines', () {
      final ctx = DiscoverGreetingContext(hour: 10, weekday: DateTime.saturday);
      for (var i = 0; i < 30; i++) {
        final t = selector.select(context: ctx, random: Random(i));
        expect(t.flavor, isNot(GreetingFlavor.weekday));
      }
    });
  });

  group('personalization balance (spec: not every time)', () {
    test('with interests set, both plain and interest-flavored lines appear across many picks', () {
      final ctx = DiscoverGreetingContext(
        hour: 14,
        weekday: DateTime.wednesday,
        interests: const {'outdoors'},
      );
      final flavors = {
        for (var i = 0; i < 200; i++) selector.select(context: ctx, random: Random(i)).flavor,
      };
      expect(flavors, contains(GreetingFlavor.interest));
      expect(
        flavors.any((f) => f != GreetingFlavor.interest),
        isTrue,
        reason: 'should not ALWAYS personalize',
      );
    });

    test('with no interests/weather/behavior signal, never returns an interest line', () {
      final ctx = DiscoverGreetingContext(hour: 14, weekday: DateTime.wednesday);
      for (var i = 0; i < 50; i++) {
        final t = selector.select(context: ctx, random: Random(i));
        expect(t.flavor, isNot(GreetingFlavor.interest));
      }
    });

    test('only returns interest lines matching the visitor\'s own selected interests', () {
      final ctx = DiscoverGreetingContext(
        hour: 14,
        weekday: DateTime.wednesday,
        interests: const {'fishing'},
      );
      for (var i = 0; i < 200; i++) {
        final t = selector.select(context: ctx, random: Random(i));
        if (t.flavor == GreetingFlavor.interest) {
          expect(t.interestToken, 'fishing');
        }
      }
    });
  });

  group('weather/behavior/returning flavors', () {
    test('rain weather can surface a rain-flavored line, never a good-weather line', () {
      final ctx = DiscoverGreetingContext(
        hour: 14,
        weekday: DateTime.wednesday,
        weatherFlavor: WeatherFlavor.rain,
      );
      final flavors = {
        for (var i = 0; i < 100; i++) selector.select(context: ctx, random: Random(i)).flavor,
      };
      expect(flavors, contains(GreetingFlavor.weatherRain));
      expect(flavors, isNot(contains(GreetingFlavor.weatherGood)));
    });

    test('a returning visitor (14+ days) can surface a "welcome back" line', () {
      final ctx = DiscoverGreetingContext(
        hour: 14,
        weekday: DateTime.wednesday,
        daysSinceLastOpen: 30,
      );
      final flavors = {
        for (var i = 0; i < 100; i++) selector.select(context: ctx, random: Random(i)).flavor,
      };
      expect(flavors, contains(GreetingFlavor.returning));
    });

    test('a same-day visitor never surfaces a "returning" line', () {
      final ctx = DiscoverGreetingContext(
        hour: 14,
        weekday: DateTime.wednesday,
        daysSinceLastOpen: 0,
      );
      for (var i = 0; i < 50; i++) {
        final t = selector.select(context: ctx, random: Random(i));
        expect(t.flavor, isNot(GreetingFlavor.returning));
      }
    });
  });

  group('recency (no obvious repeats)', () {
    test('never repeats a greeting that is in the recently-used list, when alternatives exist', () {
      final ctx = DiscoverGreetingContext(hour: 8, weekday: DateTime.tuesday);
      final eligibleIds = discoverGreetingTemplates
          .where((t) =>
              t.flavor == GreetingFlavor.generic ||
              t.flavor == GreetingFlavor.morning ||
              t.flavor == GreetingFlavor.weekday)
          .map((t) => t.id)
          .toList();
      // Exclude everything except one id — the selector must still return
      // that one remaining id rather than fail or ignore the exclusion list
      // outright.
      final excluded = eligibleIds.sublist(1);
      final t = selector.select(context: ctx, recentlyUsed: excluded, random: Random(1));
      expect(t.id, eligibleIds.first);
    });

    test('falls back gracefully (never throws) when everything eligible was recently used', () {
      final ctx = DiscoverGreetingContext(hour: 8, weekday: DateTime.tuesday);
      final allIds = discoverGreetingTemplates.map((t) => t.id).toList();
      expect(
        () => selector.select(context: ctx, recentlyUsed: allIds, random: Random(1)),
        returnsNormally,
      );
    });
  });

  group('name substitution', () {
    test('renders the with-name template when a name is present', () {
      final t = discoverGreetingTemplates.firstWhere((t) => t.id == 'g01');
      expect(t.render('Steve'), 'Hey Steve, what are you in the mood to do today?');
    });

    test('renders a genuinely different sentence (not a blank) when there is no name', () {
      final t = discoverGreetingTemplates.firstWhere((t) => t.id == 'g01');
      final rendered = t.render(null);
      expect(rendered, isNot(contains('{name}')));
      expect(rendered.trim(), isNotEmpty);
    });
  });
}
