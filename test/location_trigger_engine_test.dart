import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/gps/services/location_trigger_engine.dart';

void main() {
  group('LocationTriggerEngine', () {
    final spring = TriggerableLocation(
      id: 'spring-1',
      latitude: 29.0,
      longitude: -82.0,
      radiusMeters: 200,
    );

    test('fires arrival on entering the radius, not while already inside', () {
      final engine = LocationTriggerEngine();
      // Far away — no event.
      var events = engine.evaluate(29.5, -82.5, [spring]);
      expect(events, isEmpty);

      // Enter the radius — arrival fires.
      events = engine.evaluate(29.0, -82.0, [spring]);
      expect(events, hasLength(1));
      expect(events.first.kind, LocationTriggerKind.arrival);
      expect(events.first.locationId, 'spring-1');

      // Still inside on the next fix — no repeat.
      events = engine.evaluate(29.0001, -82.0, [spring]);
      expect(events, isEmpty);
    });

    test('arrivalTrigger=false suppresses arrival but tracks inside state',
        () {
      final silent = TriggerableLocation(
        id: 'silent-1',
        latitude: 29.0,
        longitude: -82.0,
        radiusMeters: 200,
        arrivalTrigger: false,
        departureTrigger: true,
      );
      final engine = LocationTriggerEngine();
      var events = engine.evaluate(29.0, -82.0, [silent]);
      expect(events, isEmpty); // arrival suppressed
      expect(engine.isInside('silent-1'), isTrue);

      // Leaving still fires departure, since inside-state was tracked even
      // though arrival itself never fired.
      events = engine.evaluate(29.5, -82.5, [silent]);
      expect(events, hasLength(1));
      expect(events.first.kind, LocationTriggerKind.departure);
    });

    test('departureTrigger=false (the default) never fires on leaving', () {
      final engine = LocationTriggerEngine();
      engine.evaluate(29.0, -82.0, [spring]); // arrival
      final events = engine.evaluate(29.5, -82.5, [spring]); // leave
      expect(events, isEmpty);
    });

    test('playOnce prevents any repeat firing after leaving and returning',
        () {
      final onceOnly = TriggerableLocation(
        id: 'once-1',
        latitude: 29.0,
        longitude: -82.0,
        radiusMeters: 200,
        playOnce: true,
      );
      final engine = LocationTriggerEngine();
      var events = engine.evaluate(29.0, -82.0, [onceOnly]);
      expect(events, hasLength(1)); // first arrival fires

      engine.evaluate(29.5, -82.5, [onceOnly]); // leave (no departure trigger)
      events = engine.evaluate(29.0, -82.0, [onceOnly]); // return
      expect(events, isEmpty); // playOnce blocks the repeat
    });

    test('cooldownSeconds blocks a repeat arrival within the window', () {
      final cooling = TriggerableLocation(
        id: 'cool-1',
        latitude: 29.0,
        longitude: -82.0,
        radiusMeters: 200,
        cooldownSeconds: 3600,
      );
      final engine = LocationTriggerEngine();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      var events = engine.evaluate(29.0, -82.0, [cooling], now: t0);
      expect(events, hasLength(1));

      engine.evaluate(29.5, -82.5, [cooling], now: t0.add(const Duration(minutes: 5)));
      // Return 10 minutes later — still within the 1-hour cooldown.
      events = engine.evaluate(29.0, -82.0, [cooling],
          now: t0.add(const Duration(minutes: 15)));
      expect(events, isEmpty);

      // Return again after the cooldown has fully elapsed — fires again.
      events = engine.evaluate(29.5, -82.5, [cooling],
          now: t0.add(const Duration(hours: 2)));
      events = engine.evaluate(29.0, -82.0, [cooling],
          now: t0.add(const Duration(hours: 2, minutes: 1)));
      expect(events, hasLength(1));
    });

    test('cooldown is ignored when playOnce is also set (playOnce wins)', () {
      final both = TriggerableLocation(
        id: 'both-1',
        latitude: 29.0,
        longitude: -82.0,
        radiusMeters: 200,
        playOnce: true,
        cooldownSeconds: 1, // would otherwise allow a quick repeat
      );
      final engine = LocationTriggerEngine();
      engine.evaluate(29.0, -82.0, [both]);
      engine.evaluate(29.5, -82.5, [both]);
      final events = engine.evaluate(
        29.0,
        -82.0,
        [both],
        now: DateTime.now().add(const Duration(days: 1)),
      );
      expect(events, isEmpty);
    });

    test('multiple independent locations are tracked separately', () {
      final a = TriggerableLocation(
          id: 'a', latitude: 29.0, longitude: -82.0, radiusMeters: 100);
      final b = TriggerableLocation(
          id: 'b', latitude: 30.0, longitude: -83.0, radiusMeters: 100);
      final engine = LocationTriggerEngine();
      final events = engine.evaluate(29.0, -82.0, [a, b]);
      expect(events, hasLength(1));
      expect(events.first.locationId, 'a');
    });

    test('reset() clears all tracked state', () {
      final engine = LocationTriggerEngine();
      engine.evaluate(29.0, -82.0, [spring]);
      expect(engine.isInside('spring-1'), isTrue);
      engine.reset();
      expect(engine.isInside('spring-1'), isFalse);
    });
  });
}
