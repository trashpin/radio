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
      active: active,
    );

ForestTrail _trail(String id) => ForestTrail(id: id, forestId: 'f1', trailNo: id, trailName: 'Trail $id');

void main() {
  const selector = TourSubjectSelector();

  group('selectForMovement', () {
    test('returns null when nothing arrived and no trail changed (spec: do not talk constantly)', () {
      final result = selector.selectForMovement(
        lat: 29.0,
        lng: -81.6,
        locations: [_loc('a')],
        trails: const [],
        recentlyDiscussedIds: const {},
      );
      expect(result, isNull);
    });

    test('prefers a changed trail over an arrived location', () {
      final trail = _trail('t1');
      final result = selector.selectForMovement(
        lat: 29.0,
        lng: -81.6,
        locations: [_loc('a')],
        trails: [trail],
        preferredTrailId: 't1',
        arrivedLocationIds: const {'a'},
        recentlyDiscussedIds: const {},
      );
      expect(result?.kind, TourSubjectKind.trail);
      expect(result?.id, 't1');
    });

    test('returns the nearest arrived, not-yet-discussed location', () {
      final near = _loc('near', lat: 29.0, lng: -81.6);
      final far = _loc('far', lat: 29.5, lng: -81.6);
      final result = selector.selectForMovement(
        lat: 29.0,
        lng: -81.6,
        locations: [near, far],
        trails: const [],
        arrivedLocationIds: const {'near', 'far'},
        recentlyDiscussedIds: const {},
      );
      expect(result?.id, 'near');
    });

    test('skips a recently-discussed arrival', () {
      final result = selector.selectForMovement(
        lat: 29.0,
        lng: -81.6,
        locations: [_loc('a')],
        trails: const [],
        arrivedLocationIds: const {'a'},
        recentlyDiscussedIds: const {'a'},
      );
      expect(result, isNull);
    });

    test('filters by tour type', () {
      final bird = _loc('bird', category: 'Bird Habitat');
      final result = selector.selectForMovement(
        lat: 29.0,
        lng: -81.6,
        locations: [bird],
        trails: const [],
        arrivedLocationIds: const {'bird'},
        recentlyDiscussedIds: const {},
        tourType: TourType.springsWater,
      );
      expect(result, isNull); // a bird habitat isn't a springs/water match
    });
  });

  group('selectOnDemand', () {
    test('never returns null: falls back to TourSubject.general with nothing available', () {
      final result = selector.selectOnDemand(
        lat: 29.0,
        lng: -81.6,
        locations: const [],
        trails: const [],
        recentlyDiscussedIds: const {},
      );
      expect(result.kind, TourSubjectKind.general);
      expect(result.id, 'general');
    });

    test('prefers a nearby trail when present', () {
      final trail = _trail('t1');
      final result = selector.selectOnDemand(
        lat: 29.0,
        lng: -81.6,
        locations: [_loc('a')],
        trails: [trail],
        preferredTrailId: 't1',
        recentlyDiscussedIds: const {},
      );
      expect(result.kind, TourSubjectKind.trail);
    });

    test('picks the nearest undiscussed location when no trail is nearby', () {
      final near = _loc('near', lat: 29.0, lng: -81.6);
      final far = _loc('far', lat: 29.5, lng: -81.6);
      final result = selector.selectOnDemand(
        lat: 29.0,
        lng: -81.6,
        locations: [far, near],
        trails: const [],
        recentlyDiscussedIds: const {},
      );
      expect(result.id, 'near');
    });

    test('repeats the nearest location rather than failing once everything nearby is discussed', () {
      final only = _loc('only');
      final result = selector.selectOnDemand(
        lat: 29.0,
        lng: -81.6,
        locations: [only],
        trails: const [],
        recentlyDiscussedIds: const {'only'},
      );
      expect(result.id, 'only');
    });

    test('classifies story type from storyCategory, defaulting unknowns to localStory', () {
      final folklore = _loc('f', storyCategory: 'folklore');
      final result = selector.selectOnDemand(
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
