import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/around_me/logic/anti_repeat_tracker.dart';
import 'package:explorer_os_mobile/features/around_me/logic/around_me_detector.dart';
import 'package:explorer_os_mobile/features/around_me/logic/around_me_events.dart';
import 'package:explorer_os_mobile/features/around_me/logic/explorer_score.dart';
import 'package:explorer_os_mobile/features/around_me/models/experience.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';

void main() {
  group('explorerScore', () {
    test('is bounded to 0..100', () {
      final s = explorerScore(const ExplorerScoreInput(
        distanceMeters: 0,
        radiusMeters: 1609,
        featured: true,
        recommended: true,
        seasonRelevance: 1,
        timeOfDayRelevance: 1,
        weatherRelevance: 1,
        guidePreference: 1,
      ));
      expect(s, inInclusiveRange(0, 100));
    });

    test('closer scores higher, all else equal', () {
      final near = explorerScore(
          const ExplorerScoreInput(distanceMeters: 100, radiusMeters: 1609));
      final far = explorerScore(
          const ExplorerScoreInput(distanceMeters: 1200, radiusMeters: 1609));
      expect(near, greaterThan(far));
    });

    test('featured + recommended can outrank a closer plain experience', () {
      // Not simply sorted by distance.
      final plainCloser = explorerScore(
          const ExplorerScoreInput(distanceMeters: 300, radiusMeters: 1609));
      final featuredFarther = explorerScore(const ExplorerScoreInput(
        distanceMeters: 500,
        radiusMeters: 1609,
        featured: true,
        recommended: true,
      ));
      expect(featuredFarther, greaterThan(plainCloser));
    });

    test('visited and already-played lower the score', () {
      const base = ExplorerScoreInput(distanceMeters: 200, radiusMeters: 1609);
      final baseScore = explorerScore(base);
      final visited = explorerScore(const ExplorerScoreInput(
          distanceMeters: 200, radiusMeters: 1609, previouslyVisited: true));
      final played = explorerScore(const ExplorerScoreInput(
          distanceMeters: 200,
          radiusMeters: 1609,
          narrationAlreadyPlayed: true));
      expect(visited, lessThan(baseScore));
      expect(played, lessThan(baseScore));
    });
  });

  group('AntiRepeatTracker', () {
    test('allows first trigger, blocks immediate repeat', () {
      final t = AntiRepeatTracker();
      final now = DateTime(2026, 1, 1, 12);
      expect(t.shouldTrigger('a', now: now, latitude: 29, longitude: -81),
          isTrue);
      t.markPlayed('a', now: now, latitude: 29, longitude: -81);
      expect(t.hasPlayed('a'), isTrue);
      expect(t.timesPlayed('a'), 1);
      // Same spot, moments later → blocked.
      expect(
          t.shouldTrigger('a',
              now: now.add(const Duration(seconds: 5)),
              latitude: 29,
              longitude: -81),
          isFalse);
    });

    test('re-triggers after enough time OR enough distance', () {
      final t = AntiRepeatTracker(
          minInterval: const Duration(minutes: 10), minDistanceMeters: 150);
      final now = DateTime(2026, 1, 1, 12);
      t.markPlayed('a', now: now, latitude: 29.0, longitude: -81.0);

      // Enough time later, same place → allowed.
      expect(
          t.shouldTrigger('a',
              now: now.add(const Duration(minutes: 11)),
              latitude: 29.0,
              longitude: -81.0),
          isTrue);

      // Moved far enough (~300m north), moments later → allowed.
      expect(
          t.shouldTrigger('a',
              now: now.add(const Duration(seconds: 5)),
              latitude: 29.0027,
              longitude: -81.0),
          isTrue);
    });

    test('per-visit cap blocks further triggers until a new visit', () {
      final t = AntiRepeatTracker(
          minInterval: Duration.zero, minDistanceMeters: 0, maxPerVisit: 1);
      final now = DateTime(2026, 1, 1, 12);
      t.markPlayed('a', now: now, latitude: 29, longitude: -81);
      expect(
          t.shouldTrigger('a',
              now: now.add(const Duration(minutes: 1)),
              latitude: 29,
              longitude: -81),
          isFalse);
      t.startNewVisit();
      expect(
          t.shouldTrigger('a',
              now: now.add(const Duration(minutes: 1)),
              latitude: 29,
              longitude: -81),
          isTrue);
    });
  });

  group('AroundMeDetector', () {
    NearbyRef ref(String id, double d, {bool trail = false}) =>
        (id: id, name: id, distanceMeters: d, isTrail: trail);

    test('emits NearbyExperiencesUpdated when the set changes', () {
      final det = AroundMeDetector();
      final now = DateTime(2026);
      final e1 = det.update(
        now: now,
        nearby: [ref('a', 500), ref('b', 800)],
        triggerRadiusMeters: 150,
        movement: MovementState.moving,
      );
      expect(e1.whereType<NearbyExperiencesUpdated>(), isNotEmpty);
      // Same set again → no new update event.
      final e2 = det.update(
        now: now,
        nearby: [ref('a', 480), ref('b', 790)],
        triggerRadiusMeters: 150,
        movement: MovementState.moving,
      );
      expect(e2.whereType<NearbyExperiencesUpdated>(), isEmpty);
    });

    test('emits EnteredPoi/ExitedPoi crossing the trigger radius', () {
      final det = AroundMeDetector();
      final now = DateTime(2026);
      // Far → no enter.
      det.update(
          now: now,
          nearby: [ref('a', 500)],
          triggerRadiusMeters: 150,
          movement: MovementState.moving);
      // Within radius → EnteredPoi once.
      final enter = det.update(
          now: now,
          nearby: [ref('a', 100)],
          triggerRadiusMeters: 150,
          movement: MovementState.moving);
      expect(enter.whereType<EnteredPoi>().map((e) => e.id), contains('a'));
      // Still inside → no duplicate enter.
      final stay = det.update(
          now: now,
          nearby: [ref('a', 90)],
          triggerRadiusMeters: 150,
          movement: MovementState.moving);
      expect(stay.whereType<EnteredPoi>(), isEmpty);
      // Move away → ExitedPoi.
      final exit = det.update(
          now: now,
          nearby: [ref('a', 400)],
          triggerRadiusMeters: 150,
          movement: MovementState.moving);
      expect(exit.whereType<ExitedPoi>().map((e) => e.id), contains('a'));
    });

    test('emits VehicleStopped/Moving and ZoneChanged transitions', () {
      final det = AroundMeDetector();
      final now = DateTime(2026);
      det.update(
          now: now,
          nearby: const [],
          triggerRadiusMeters: 150,
          movement: MovementState.moving,
          zone: 'Ocala');
      final stopped = det.update(
          now: now,
          nearby: const [],
          triggerRadiusMeters: 150,
          movement: MovementState.stopped,
          zone: 'Ocala');
      expect(stopped.whereType<VehicleStopped>(), isNotEmpty);
      final zoned = det.update(
          now: now,
          nearby: const [],
          triggerRadiusMeters: 150,
          movement: MovementState.stopped,
          zone: 'Juniper Springs');
      expect(zoned.whereType<ZoneChanged>(), isNotEmpty);
    });

    test('emits GpsSignalLost then GpsSignalRestored', () {
      final det = AroundMeDetector();
      final now = DateTime(2026);
      det.update(
          now: now,
          nearby: const [],
          triggerRadiusMeters: 150,
          movement: MovementState.moving);
      final lost = det.update(
          now: now,
          nearby: const [],
          triggerRadiusMeters: 150,
          movement: MovementState.moving,
          gpsAvailable: false);
      expect(lost.whereType<GpsSignalLost>(), isNotEmpty);
      final restored = det.update(
          now: now,
          nearby: const [],
          triggerRadiusMeters: 150,
          movement: MovementState.moving,
          gpsAvailable: true);
      expect(restored.whereType<GpsSignalRestored>(), isNotEmpty);
    });
  });

  group('Experience', () {
    test('derives compass direction from bearing', () {
      const e = Experience(
        id: 'x',
        name: 'X',
        category: 'springs',
        latitude: 29.1,
        longitude: -81.7,
        distanceMeters: 100,
        bearingDegrees: 90,
        score: 50,
      );
      expect(e.direction, CardinalDirection.east);
      expect(cardinalShort(e.direction), 'E');
      expect(e.isTrail, isFalse);
    });

    test('detects trail category', () {
      const e = Experience(
        id: 't',
        name: 'Yearling Trail',
        category: 'trails',
        latitude: 0,
        longitude: 0,
        distanceMeters: 10,
        bearingDegrees: 0,
        score: 1,
      );
      expect(e.isTrail, isTrue);
    });
  });
}
