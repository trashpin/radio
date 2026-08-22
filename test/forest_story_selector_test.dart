// Unit tests for ForestStorySelector — mirrors GpsStorySelector's own test
// shape (lib/features/story_studio/services/gps_story_selector.dart),
// reimplemented against ForestLocation since the two live in deliberately
// isolated tables.

import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/services/forest_story_selector.dart';
import 'package:flutter_test/flutter_test.dart';

ForestLocation _story(
  String id, {
  double lat = 29.0,
  double lng = -81.6,
  double? geofenceRadiusMeters,
  bool active = true,
  String? storyCategory,
}) =>
    ForestLocation(
      id: id,
      forestId: 'forest-1',
      name: 'Story $id',
      category: 'Story',
      latitude: lat,
      longitude: lng,
      geofenceRadiusMeters: geofenceRadiusMeters,
      active: active,
      experienceType: 'story',
      storyCategory: storyCategory,
    );

void main() {
  group('ForestStorySelector', () {
    test('inRange only returns story-type, active, in-radius locations', () {
      final selector = ForestStorySelector();
      final inRange = _story('a', lat: 29.0, lng: -81.6, geofenceRadiusMeters: 500);
      final tooFar = _story('b', lat: 29.1, lng: -81.6, geofenceRadiusMeters: 500);
      final inactive =
          _story('c', lat: 29.0, lng: -81.6, geofenceRadiusMeters: 500, active: false);
      final notAStory = ForestLocation(
        id: 'd',
        forestId: 'forest-1',
        name: 'Discovery',
        category: 'Spring',
        latitude: 29.0,
        longitude: -81.6,
        geofenceRadiusMeters: 500,
      ); // experienceType defaults to 'discovery'

      final result =
          selector.inRange([inRange, tooFar, inactive, notAStory], 29.0, -81.6);
      expect(result.map((s) => s.id), ['a']);
    });

    test('filters by storyCategory when provided', () {
      final selector = ForestStorySelector();
      final wildlife = _story('a', geofenceRadiusMeters: 500, storyCategory: 'WILDLIFE');
      final history = _story('b', geofenceRadiusMeters: 500, storyCategory: 'HISTORY');

      final result = selector.inRange([wildlife, history], 29.0, -81.6,
          storyCategory: 'HISTORY');
      expect(result.map((s) => s.id), ['b']);
    });

    test('select returns null when nothing is in range', () {
      final selector = ForestStorySelector();
      expect(selector.select(const [], 29.0, -81.6), isNull);
    });

    test('select avoids already-played stories unless none remain', () {
      final selector = ForestStorySelector();
      final a = _story('a', geofenceRadiusMeters: 500);
      final b = _story('b', geofenceRadiusMeters: 500);

      // Both in range, 'a' already played -> must pick 'b'.
      final pick = selector.select([a, b], 29.0, -81.6, alreadyPlayed: {'a'});
      expect(pick?.id, 'b');

      // Both already played -> falls back to the full eligible pool.
      final fallback =
          selector.select([a, b], 29.0, -81.6, alreadyPlayed: {'a', 'b'});
      expect(fallback, isNotNull);
      expect({'a', 'b'}.contains(fallback!.id), isTrue);
    });
  });
}
