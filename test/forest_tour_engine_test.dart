import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/services/forest_tour_engine.dart';
import 'package:flutter_test/flutter_test.dart';

ForestLocation _loc(String id, {double lat = 29.0, double lng = -81.6, double? radius}) =>
    ForestLocation(
      id: id,
      forestId: 'f1',
      name: 'Location $id',
      category: 'Spring',
      latitude: lat,
      longitude: lng,
      geofenceRadiusMeters: radius,
    );

GPSLocation _fix(double lat, double lng) =>
    GPSLocation(latitude: lat, longitude: lng, timestamp: DateTime(2026, 1, 1));

void main() {
  group('ForestTourEngine.onLocation', () {
    test('fires on first arrival at a location', () {
      final engine = ForestTourEngine();
      final loc = _loc('a', radius: 200);
      final subject = engine.onLocation(
        fix: _fix(29.0, -81.6),
        locations: [loc],
        trails: const [],
        recentlyDiscussedIds: const {},
        now: DateTime(2026, 1, 1, 12, 0, 0),
      );
      expect(subject?.id, 'a');
    });

    test('stays quiet immediately after firing, even at a genuinely new nearby location (cooldown)', () {
      // ~50m separates the two fixes/locations -- close enough to be a real,
      // distinct arrival, but under both this test's distance AND time
      // cooldown thresholds, so it must be suppressed.
      final engine = ForestTourEngine(minSecondsBetweenSegments: 90, minMetersBetweenSegments: 120);
      final loc = _loc('a', lat: 29.0, lng: -81.6, radius: 30);
      final nearbyLoc = _loc('b', lat: 29.00045, lng: -81.6, radius: 30);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      final first = engine.onLocation(
        fix: _fix(29.0, -81.6),
        locations: [loc, nearbyLoc],
        trails: const [],
        recentlyDiscussedIds: const {},
        now: t0,
      );
      expect(first?.id, 'a');

      // 10 seconds later, arrived at a second, genuinely distinct location
      // (~50m away) -- still within the cooldown window (neither enough
      // time nor enough distance), so the tour stays quiet.
      final second = engine.onLocation(
        fix: _fix(29.00045, -81.6),
        locations: [loc, nearbyLoc],
        trails: const [],
        recentlyDiscussedIds: const {},
        now: t0.add(const Duration(seconds: 10)),
      );
      expect(second, isNull);
    });

    test('fires again once the time cooldown has elapsed, even without much movement', () {
      // minMetersBetweenSegments is huge, so ONLY the elapsed-time
      // threshold can be satisfied here -- proving time alone is enough to
      // re-allow narration (the two thresholds are independent "OR"
      // conditions to allow, not both required).
      final engine = ForestTourEngine(minSecondsBetweenSegments: 90, minMetersBetweenSegments: 5000);
      final a = _loc('a', lat: 29.0, lng: -81.6, radius: 30);
      final b = _loc('b', lat: 29.0005, lng: -81.6, radius: 30); // ~55m away
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      engine.onLocation(
        fix: _fix(29.0, -81.6),
        locations: [a, b],
        trails: const [],
        recentlyDiscussedIds: const {},
        now: t0,
      );

      final later = engine.onLocation(
        fix: _fix(29.0005, -81.6),
        locations: [a, b],
        trails: const [],
        recentlyDiscussedIds: const {'a'},
        now: t0.add(const Duration(seconds: 120)),
      );
      expect(later?.id, 'b');
    });

    test('a trail change takes priority over a location arrival', () {
      final engine = ForestTourEngine();
      final loc = _loc('a', radius: 5000);
      final trail = ForestTrail(
        id: 't1',
        forestId: 'f1',
        trailNo: '0001',
        parts: [
          [(lat: 29.0, lng: -81.6)],
        ],
      );
      final subject = engine.onLocation(
        fix: _fix(29.0, -81.6),
        locations: [loc],
        trails: [trail],
        recentlyDiscussedIds: const {},
        now: DateTime(2026, 1, 1, 12, 0, 0),
      );
      expect(subject?.id, 't1');
    });

    test('returns null when nothing is nearby at all', () {
      final engine = ForestTourEngine();
      final subject = engine.onLocation(
        fix: _fix(29.0, -81.6),
        locations: const [],
        trails: const [],
        recentlyDiscussedIds: const {},
        now: DateTime(2026, 1, 1, 12, 0, 0),
      );
      expect(subject, isNull);
    });
  });

  group('ForestTourEngine.onDemand', () {
    test('never returns null, even with nothing loaded', () {
      final engine = ForestTourEngine();
      final subject = engine.onDemand(
        lat: 29.0,
        lng: -81.6,
        locations: const [],
        trails: const [],
        recentlyDiscussedIds: const {},
      );
      expect(subject.kind.toString(), contains('general'));
    });

    test('resets the movement cooldown so the next passive check starts fresh', () {
      final engine = ForestTourEngine(minSecondsBetweenSegments: 9999, minMetersBetweenSegments: 9999);
      final loc = _loc('a', radius: 5000);
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      engine.onDemand(
        lat: 29.0,
        lng: -81.6,
        locations: [loc],
        trails: const [],
        recentlyDiscussedIds: const {},
        now: t0,
      );

      // Immediately after an on-demand pick, the passive engine's cooldown
      // should still suppress a new arrival (on-demand doesn't bypass the
      // cooldown for what comes right after it).
      final passive = engine.onLocation(
        fix: _fix(29.0, -81.6),
        locations: [loc],
        trails: const [],
        recentlyDiscussedIds: const {},
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(passive, isNull);
    });
  });
}
