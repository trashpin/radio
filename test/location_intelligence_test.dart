import 'package:explorer_os_mobile/features/location_intelligence/location_intelligence.dart';
import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart';
import 'package:flutter_test/flutter_test.dart';

// Approx latitude offset (degrees) for a given distance in miles from (0,0).
double _lat(double miles) => miles * 1609.344 / 111320.0;

ContentItem _item(
  String id,
  ContentCategory cat, {
  double miles = 0.5,
  String? county,
  String? city,
  String? state,
  String? park,
  double? radiusMeters,
  Duration cooldown = const Duration(hours: 6),
  DateTime? lastPlayed,
}) =>
    ContentItem(
      id: id,
      title: '$id (${cat.id})',
      category: cat,
      latitude: _lat(miles),
      longitude: 0,
      county: county,
      city: city,
      state: state,
      park: park,
      radiusMeters: radiusMeters,
      cooldown: cooldown,
      lastPlayed: lastPlayed,
      audioUrl: 'https://a/$id.mp3',
    );

const _engine = LocationIntelligenceEngine();

void main() {
  group('priorityForDistance', () {
    test('distance bands match the spec', () {
      expect(priorityForDistance(0.5 * 1609.344), 100);
      expect(priorityForDistance(1 * 1609.344), 100);
      expect(priorityForDistance(2 * 1609.344), 90);
      expect(priorityForDistance(4 * 1609.344), 80);
      expect(priorityForDistance(8 * 1609.344), 60);
      expect(priorityForDistance(15 * 1609.344), 40);
      expect(priorityForDistance(25 * 1609.344), 0);
    });
  });

  group('deriveContext', () {
    test('excludes content beyond 20 miles and ranks nearest-first', () {
      final ctx = _engine.deriveContext(0, 0, [
        _item('near', ContentCategory.wildlife, miles: 0.5),
        _item('mid', ContentCategory.history, miles: 4),
        _item('far', ContentCategory.attraction, miles: 25),
      ]);
      expect(ctx.nearby.map((r) => r.item.id), ['near', 'mid']);
      expect(ctx.nearby.first.priority, 100);
    });

    test('geocodes county/city/state/park from the nearest carrying content', () {
      final ctx = _engine.deriveContext(0, 0, [
        _item('c', ContentCategory.countyHistory, miles: 0.4, county: 'Marion'),
        _item('t', ContentCategory.cityIntro, miles: 2, city: 'Ocala', state: 'Florida'),
        _item('p', ContentCategory.park,
            miles: 0.6, park: 'Ocala National Forest', radiusMeters: 8000),
      ]);
      expect(ctx.county, 'Marion');
      expect(ctx.city, 'Ocala');
      expect(ctx.state, 'Florida');
      expect(ctx.park, 'Ocala National Forest');
    });

    test('does not claim a park that is far outside its radius', () {
      final ctx = _engine.deriveContext(0, 0, [
        _item('p', ContentCategory.park,
            miles: 12, park: 'Distant SP', radiusMeters: 3000),
      ]);
      expect(ctx.park, isNull);
    });
  });

  group('rankNearby eligibility', () {
    test('skips already-played and cooled-down items', () {
      final now = DateTime(2026, 7, 28, 12);
      final ctx = _engine.deriveContext(0, 0, [
        _item('a', ContentCategory.wildlife, miles: 0.5),
        _item('b', ContentCategory.history, miles: 0.6),
        _item('c', ContentCategory.plants,
            miles: 0.7,
            cooldown: const Duration(hours: 2),
            lastPlayed: now.subtract(const Duration(minutes: 30))),
      ]);
      final trip = TripState()..played.add('a');
      final eligible = _engine.rankNearby(ctx, trip, now: now).map((r) => r.item.id);
      expect(eligible, ['b'], reason: 'a played, c still cooling down');
    });
  });

  group('transitions', () {
    test('detects entered county/city/park and left park', () {
      final ctx = _engine.deriveContext(0, 0, [
        _item('c', ContentCategory.countyHistory, miles: 0.4, county: 'Marion'),
        _item('p', ContentCategory.arrival,
            miles: 0.5, park: 'Ocala NF', radiusMeters: 8000),
      ]);
      final trip = TripState();
      final t = _engine.pendingTransitions(ctx, trip);
      expect(t, containsAll([
        LocationTransition.enteredCounty,
        LocationTransition.enteredPark,
      ]));

      final left = TripState()..currentPark = 'Ocala NF';
      final noPark = _engine.deriveContext(0, 0, [
        _item('c', ContentCategory.countyHistory, miles: 0.4, county: 'Marion'),
      ]);
      expect(_engine.pendingTransitions(noPark, left),
          contains(LocationTransition.leftPark));
    });

    test('entering a county plays a county welcome first', () {
      final ctx = _engine.deriveContext(0, 0, [
        _item('welcome', ContentCategory.countyHistory, miles: 0.4, county: 'Marion'),
        _item('song_area', ContentCategory.wildlife, miles: 0.5),
      ]);
      final trip = TripState();
      final d = _engine.next(ctx, trip, now: DateTime(2026, 7, 28, 12));
      expect(d.kind, RadioSlotKind.narration);
      expect(d.transition, LocationTransition.enteredCounty);
      expect(d.item!.id, 'welcome');
      expect(trip.currentCounty, 'Marion');
    });
  });

  group('opening programming order (whole journey, parks last)', () {
    test('tells the area story before the park: county → city → community → '
        'river → landmark → scenic', () {
      // No county/city fields → no transitions; tests the phase machine purely.
      final items = [
        _item('welcome', ContentCategory.welcome),
        _item('cwelcome', ContentCategory.countyWelcome),
        _item('chist', ContentCategory.countyHistory),
        _item('citywelcome', ContentCategory.cityWelcome),
        _item('community', ContentCategory.communityStory),
        _item('river', ContentCategory.riverStory),
        _item('landmark', ContentCategory.historicLandmark),
        _item('scenic', ContentCategory.scenicDrive),
        _item('wildlife', ContentCategory.wildlife),
      ];
      final ctx = _engine.deriveContext(0, 0, items);
      final trip = TripState();
      final now = DateTime(2026, 7, 28, 12);

      final narrations = <String>[];
      for (var i = 0; i < 24; i++) {
        final d = _engine.next(ctx, trip, now: now);
        if (d.kind == RadioSlotKind.narration) narrations.add(d.item!.id);
      }
      // The area's story leads; the park layer (wildlife) comes after.
      expect(narrations.take(7).toList(), [
        'welcome',
        'cwelcome',
        'chist',
        'citywelcome',
        'community',
        'river',
        'landmark',
      ]);
      expect(narrations.indexOf('scenic'),
          lessThan(narrations.indexOf('wildlife')),
          reason: 'scenic drive (area) airs before wildlife (park layer)');
    });
  });

  group('music balance + anti-repeat', () {
    test('never plays more than three songs in a row', () {
      // No narration content at all → engine leans on music + dj breaks.
      final ctx = _engine.deriveContext(0, 0, const []);
      final trip = TripState();
      final now = DateTime(2026, 7, 28, 12);
      var run = 0, maxRun = 0;
      for (var i = 0; i < 40; i++) {
        final d = _engine.next(ctx, trip, now: now);
        if (d.kind == RadioSlotKind.music) {
          run++;
          maxRun = run > maxRun ? run : maxRun;
        } else {
          run = 0;
        }
      }
      expect(maxRun, lessThanOrEqualTo(3));
    });

    test('never repeats a narration within a trip', () {
      final items = [
        for (var i = 0; i < 6; i++)
          _item('w$i', ContentCategory.wildlife, miles: 0.5 + i * 0.1),
        for (var i = 0; i < 6; i++)
          _item('h$i', ContentCategory.history, miles: 0.5 + i * 0.1),
      ];
      final ctx = _engine.deriveContext(0, 0, items);
      final trip = TripState()
        ..currentCounty = ctx.county
        ..currentCity = ctx.city
        ..currentPark = ctx.park;
      final now = DateTime(2026, 7, 28, 12);
      final heard = <String>[];
      for (var i = 0; i < 40; i++) {
        final d = _engine.next(ctx, trip, now: now);
        if (d.kind == RadioSlotKind.narration) heard.add(d.item!.id);
      }
      expect(heard.length, heard.toSet().length,
          reason: 'no narration repeats within the trip');
    });
  });
}
