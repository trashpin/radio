import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_subject.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_type.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/services/tour_subject_selector.dart';
import 'package:flutter_test/flutter_test.dart';

ForestLocation _loc(
  String id, {
  double lat = 29.0,
  double lng = -81.6,
  String category = 'Spring',
  String? storyCategory,
  double? radius,
  bool active = true,
}) =>
    ForestLocation(
      id: id,
      forestId: 'f1',
      name: 'Location $id',
      category: category,
      latitude: lat,
      longitude: lng,
      storyCategory: storyCategory,
      geofenceRadiusMeters: radius,
      active: active,
    );

ForestTrail _trailAt(String id, double lat, double lng) => ForestTrail(
      id: id,
      forestId: 'f1',
      trailNo: id,
      trailName: 'Trail $id',
      parts: [
        [(lat: lat, lng: lng)],
      ],
    );

void main() {
  const selector = TourSubjectSelector();

  group('rank — priority order (spec §4/§8)', () {
    test('an exact geofence match outranks a nearby-but-not-arrived one', () {
      final exact = _loc('exact', lat: 29.0, lng: -81.6, radius: 50); // visitor is right at it
      final nearby = _loc('nearby', lat: 29.001, lng: -81.6, radius: 20); // ~111m away, outside its own radius
      final result = selector.rank(
        lat: 29.0,
        lng: -81.6,
        locations: [nearby, exact],
        trails: const [],
        recentlyDiscussedIds: const {},
      );
      expect(result?.id, 'exact');
    });

    test('an exact geofence match outranks being on a trail', () {
      final loc = _loc('a', lat: 29.0, lng: -81.6, radius: 50);
      final trail = _trailAt('t1', 29.0, -81.6); // also right here
      final result = selector.rank(
        lat: 29.0,
        lng: -81.6,
        locations: [loc],
        trails: [trail],
        recentlyDiscussedIds: const {},
      );
      expect(result?.kind, TourSubjectKind.location);
      expect(result?.id, 'a');
    });

    test('being on a trail outranks a merely nearby (not exact) geofence', () {
      final nearbyGeofence = _loc('a', lat: 29.001, lng: -81.6, radius: 20); // ~111m, "nearby geofence" tier
      final trail = _trailAt('t1', 29.0, -81.6); // visitor is standing right on it
      final result = selector.rank(
        lat: 29.0,
        lng: -81.6,
        locations: [nearbyGeofence],
        trails: [trail],
        recentlyDiscussedIds: const {},
      );
      expect(result?.kind, TourSubjectKind.trail);
    });

    test('a nearby trail outranks a farther, non-exact location', () {
      final farLocation = _loc('a', lat: 29.03, lng: -81.6, radius: 20); // ~3.3km, well outside "near geofence"
      final nearTrail = _trailAt('t1', 29.003, -81.6); // ~333m -- within "nearby trail" (500m) but not "on" it
      final result = selector.rank(
        lat: 29.0,
        lng: -81.6,
        locations: [farLocation],
        trails: [nearTrail],
        recentlyDiscussedIds: const {},
      );
      expect(result?.kind, TourSubjectKind.trail);
    });

    test('never reaches across the whole forest: nothing beyond the max relevant radius is returned', () {
      final tooFar = _loc('a', lat: 29.2, lng: -81.6); // ~22km away
      final result = selector.rank(
        lat: 29.0,
        lng: -81.6,
        locations: [tooFar],
        trails: const [],
        recentlyDiscussedIds: const {},
      );
      expect(result, isNull);
    });

    test('skips recently-discussed candidates and filters by tour type', () {
      final discussed = _loc('a', radius: 50);
      final wrongType = _loc('b', category: 'Bird Habitat', radius: 50);
      final r1 = selector.rank(
        lat: 29.0,
        lng: -81.6,
        locations: [discussed],
        trails: const [],
        recentlyDiscussedIds: const {'a'},
      );
      expect(r1, isNull);

      final r2 = selector.rank(
        lat: 29.0,
        lng: -81.6,
        locations: [wrongType],
        trails: const [],
        recentlyDiscussedIds: const {},
        tourType: TourType.springsWater,
      );
      expect(r2, isNull);
    });
  });

  group('rank — isExactMatch (spec §18/§19)', () {
    test('a location within its own geofence radius is flagged exact', () {
      final loc = _loc('a', lat: 29.0, lng: -81.6, radius: 200);
      final result = selector.rank(
        lat: 29.0,
        lng: -81.6,
        locations: [loc],
        trails: const [],
        recentlyDiscussedIds: const {},
      );
      expect(result?.isExactMatch, isTrue);
    });

    test('a location outside its own geofence radius (merely nearby) is flagged not exact', () {
      final loc = _loc('a', lat: 29.001, lng: -81.6, radius: 20); // ~111m away, radius only 20m
      final result = selector.rank(
        lat: 29.0,
        lng: -81.6,
        locations: [loc],
        trails: const [],
        recentlyDiscussedIds: const {},
      );
      expect(result?.isExactMatch, isFalse);
    });

    test('being right on a trail is flagged exact; a merely nearby trail is not', () {
      final onTrail = _trailAt('on', 29.0, -81.6);
      final r1 = selector.rank(
        lat: 29.0,
        lng: -81.6,
        locations: const [],
        trails: [onTrail],
        recentlyDiscussedIds: const {},
      );
      expect(r1?.isExactMatch, isTrue);

      final nearTrail = _trailAt('near', 29.003, -81.6); // ~333m away
      final r2 = selector.rank(
        lat: 29.0,
        lng: -81.6,
        locations: const [],
        trails: [nearTrail],
        recentlyDiscussedIds: const {},
      );
      expect(r2?.isExactMatch, isFalse);
    });

    test('TourSubject.general is never exact', () {
      expect(TourSubject.general.isExactMatch, isFalse);
    });
  });

  group('rankOnDemand', () {
    test('never returns null: falls back to TourSubject.general with nothing available', () {
      final result = selector.rankOnDemand(
        lat: 29.0,
        lng: -81.6,
        locations: const [],
        trails: const [],
        recentlyDiscussedIds: const {},
      );
      expect(result.kind, TourSubjectKind.general);
    });

    test('repeats the nearest candidate rather than failing once everything nearby is discussed', () {
      final only = _loc('only', radius: 50);
      final result = selector.rankOnDemand(
        lat: 29.0,
        lng: -81.6,
        locations: [only],
        trails: const [],
        recentlyDiscussedIds: const {'only'},
      );
      expect(result.id, 'only');
    });

    test('classifies story type from storyCategory, defaulting unknowns to localStory', () {
      final folklore = _loc('f', storyCategory: 'folklore', radius: 50);
      final result = selector.rankOnDemand(
        lat: 29.0,
        lng: -81.6,
        locations: [folklore],
        trails: const [],
        recentlyDiscussedIds: const {},
      );
      expect(result.storyType.isUnverified, isTrue);
    });
  });
}
