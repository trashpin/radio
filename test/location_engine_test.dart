import 'package:explorer_os_mobile/features/locations/location_engine.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter_test/flutter_test.dart';

double _lat(double miles) => miles * 1609.344 / 111320.0;

MasterLocation _loc(
  String id,
  String name,
  LocationType type, {
  double miles = 0.5,
  int priority = 0,
  bool active = true,
  bool hidden = false,
  String? county,
  String? city,
  double? triggerRadius,
  ContentStatus? contentStatus,
}) =>
    MasterLocation(
      id: id,
      name: name,
      type: type,
      latitude: _lat(miles),
      longitude: 0,
      priority: priority,
      active: active,
      hidden: hidden,
      county: county,
      city: city,
      triggerRadius: triggerRadius,
      contentStatus: contentStatus,
    );

const _engine = LocationEngine();

void main() {
  group('LocationType', () {
    test('covers all types and maps free-form categories', () {
      expect(LocationType.values.length, 50);
      expect(LocationType.fromId('state_park'), LocationType.statePark);
      expect(LocationType.fromId('Silver Springs'), LocationType.spring);
      expect(LocationType.fromId('Ocklawaha River'), LocationType.river);
      expect(LocationType.fromId('Ocala National Forest'),
          LocationType.nationalForest);
      expect(LocationType.fromId('Historic Fort'), LocationType.historicSite);
      expect(LocationType.fromId('mystery'), LocationType.pointOfInterest);
    });
  });

  group('distanceBand', () {
    test('matches the priority bands', () {
      expect(distanceBand(0.5 * 1609.344), 100);
      expect(distanceBand(4 * 1609.344), 80);
      expect(distanceBand(25 * 1609.344), 0);
    });
  });

  group('nearby', () {
    final all = [
      _loc('near', 'Near Spring', LocationType.spring, miles: 0.5),
      _loc('mid', 'Mid Museum', LocationType.museum, miles: 4),
      _loc('far', 'Far Attraction', LocationType.attraction, miles: 25),
      _loc('hidden', 'Hidden', LocationType.hiddenGem, miles: 0.4, hidden: true),
      _loc('inactive', 'Inactive', LocationType.trail, miles: 0.4, active: false),
    ];

    test('excludes >20mi, hidden, inactive; ranks nearest-first', () {
      final r = _engine.nearby(0, 0, all);
      expect(r.map((e) => e.location.id), ['near', 'mid']);
    });

    test('priority boosts a farther location above a nearer one', () {
      final list = [
        _loc('a', 'A', LocationType.museum, miles: 1),
        _loc('b', 'B', LocationType.attraction, miles: 3, priority: 50),
      ];
      expect(_engine.topNearby(0, 0, list)!.location.id, 'b');
    });

    test('type filter + exclude set are honored', () {
      final r = _engine.nearby(0, 0, all,
          types: {LocationType.museum}, exclude: {});
      expect(r.map((e) => e.location.id), ['mid']);
      final r2 = _engine.nearby(0, 0, all, exclude: {'near'});
      expect(r2.map((e) => e.location.id), ['mid']);
    });

    test('a location within its trigger radius stays eligible', () {
      final list = [
        _loc('t', 'Trigger', LocationType.safetyAlert,
            miles: 30, triggerRadius: 60000), // ~37mi radius
      ];
      expect(_engine.nearby(0, 0, list).map((e) => e.location.id), ['t']);
    });
  });

  group('mapLocations', () {
    test('filters by radius + type, drops hidden/inactive', () {
      final all = [
        _loc('a', 'A', LocationType.spring, miles: 2),
        _loc('b', 'B', LocationType.restaurant, miles: 50),
        _loc('c', 'C', LocationType.spring, miles: 1, hidden: true),
      ];
      final shown = _engine.mapLocations(all,
          centerLat: 0, centerLng: 0, maxMiles: 20);
      expect(shown.map((l) => l.id), ['a']);
      final springs = _engine.mapLocations(all, types: {LocationType.spring});
      expect(springs.map((l) => l.id), ['a']); // c hidden, b filtered by type
    });
  });

  group('search', () {
    final all = [
      _loc('lb', 'Lake Bryant', LocationType.lake, county: 'Marion'),
      _loc('ss', 'Silver Springs', LocationType.spring, county: 'Marion'),
      _loc('lbrd', 'Lake Bryant Road', LocationType.scenicRoad),
    ];
    test('prefix matches rank first; searches name + meta', () {
      final r = _engine.search('lake bryant', all);
      expect(r.first.id, 'lb');
      expect(r.map((l) => l.id), containsAll(['lb', 'lbrd']));
    });
    test('finds by county metadata', () {
      final r = _engine.search('marion', all);
      expect(r.map((l) => l.id), containsAll(['lb', 'ss']));
    });
    test('empty query returns nothing', () {
      expect(_engine.search('   ', all), isEmpty);
    });

    test('search excludes DISABLED (hidden/inactive) locations', () {
      final withHidden = [
        ...all,
        _loc('hidden', 'Lake Hidden', LocationType.lake, hidden: true),
        MasterLocation(
            id: 'inactive', name: 'Lake Inactive', type: LocationType.lake,
            latitude: 29, longitude: -82, active: false),
      ];
      final r = _engine.search('lake', withHidden);
      expect(r.map((l) => l.id), isNot(contains('hidden')));
      expect(r.map((l) => l.id), isNot(contains('inactive')));
    });
  });

  group('requireAudio', () {
    MasterLocation withAudio(String id, double miles, {List<String> audio = const []}) =>
        MasterLocation(
            id: id, name: id, type: LocationType.spring,
            latitude: _lat(miles), longitude: 0, audioFiles: audio);
    final list = [
      withAudio('silent', 0.3),
      withAudio('narrated', 1.0, audio: ['http://x/a.mp3']),
    ];
    test('skips silent locations and picks the next nearest narrated', () {
      final top = _engine.topNearby(0, 0, list, requireAudio: true);
      expect(top!.location.id, 'narrated');
    });
    test('without requireAudio the nearest (silent) wins', () {
      expect(_engine.topNearby(0, 0, list)!.location.id, 'silent');
    });
  });

  group('publish gating (content_status)', () {
    test('isPublishBlocked only for explicit draft/archived; null grandfathered',
        () {
      expect(_loc('a', 'A', LocationType.museum).isPublishBlocked, isFalse);
      expect(
          _loc('a', 'A', LocationType.museum,
                  contentStatus: ContentStatus.draft)
              .isPublishBlocked,
          isTrue);
      expect(
          _loc('a', 'A', LocationType.museum,
                  contentStatus: ContentStatus.archived)
              .isPublishBlocked,
          isTrue);
      expect(
          _loc('a', 'A', LocationType.museum,
                  contentStatus: ContentStatus.published)
              .isPublishBlocked,
          isFalse);
      expect(
          _loc('a', 'A', LocationType.museum,
                  contentStatus: ContentStatus.needsReview)
              .isPublishBlocked,
          isFalse);
    });

    test('draft locations are excluded from nearby, search, and map', () {
      final draft = _loc('d', 'Draft Diner', LocationType.restaurant,
          miles: 0.4, contentStatus: ContentStatus.draft);
      final live = _loc('p', 'Published Park', LocationType.cityPark,
          miles: 0.5, contentStatus: ContentStatus.published);
      final legacy =
          _loc('l', 'Legacy Lake', LocationType.lake, miles: 0.6); // null
      final all = [draft, live, legacy];

      final nearbyIds =
          _engine.nearby(0, 0, all).map((n) => n.location.id).toSet();
      expect(nearbyIds, {'p', 'l'});
      expect(nearbyIds, isNot(contains('d')));

      final searchIds =
          _engine.search('a', all).map((l) => l.id).toSet(); // matches all names
      expect(searchIds.contains('d'), isFalse);
      expect(searchIds, containsAll(<String>['p', 'l']));

      final mapIds = _engine.mapLocations(all).map((l) => l.id).toSet();
      expect(mapIds, {'p', 'l'});
    });

    test('publishing a formerly-draft location makes it visible again', () {
      final draft = _loc('d', 'Draft Diner', LocationType.restaurant,
          contentStatus: ContentStatus.draft);
      expect(_engine.nearby(0, 0, [draft]), isEmpty);
      final published = draft.copyWith(contentStatus: ContentStatus.published);
      expect(_engine.nearby(0, 0, [published]).single.location.id, 'd');
    });
  });
}
