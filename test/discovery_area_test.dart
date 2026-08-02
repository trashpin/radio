import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

MasterLocation _area({
  required String id,
  required String name,
  required double lat,
  required double lng,
  required double radius,
  int? estimatedListeningMinutes,
  String? narrationScript,
  List<String> images = const [],
  String? shortDescription,
  bool active = true,
  bool hidden = false,
}) =>
    MasterLocation.fromJson({
      'id': id,
      'name': name,
      'category': 'area',
      'latitude': lat,
      'longitude': lng,
      'trigger_radius': radius,
      'estimated_listening_minutes': estimatedListeningMinutes,
      'narration_script': narrationScript,
      'images': images,
      'short_description': shortDescription,
      'active': active,
      'hidden': hidden,
    });

void main() {
  group('LocationType.area', () {
    test('exact id matches the area type', () {
      expect(LocationType.fromId('area'), LocationType.area);
    });
  });

  group('detectCurrentArea', () {
    test('returns null when there are no area-type locations', () {
      final result = detectCurrentArea(const [], 29.0, -82.0);
      expect(result, isNull);
    });

    test('returns the area the traveler is inside', () {
      final ocalaForest = _area(
        id: '1',
        name: 'Ocala National Forest',
        lat: 29.2,
        lng: -81.9,
        radius: 20000,
      );
      final result = detectCurrentArea([ocalaForest], 29.2, -81.9);
      expect(result?.name, 'Ocala National Forest');
      expect(result?.isCurrentlyInside, isTrue);
    });

    test('when inside two overlapping areas, the more specific (smaller '
        'radius) one wins', () {
      final forest = _area(
        id: '1',
        name: 'Ocala National Forest',
        lat: 29.2,
        lng: -81.9,
        radius: 20000,
      );
      final downtown = _area(
        id: '2',
        name: 'Historic Downtown Ocala',
        lat: 29.2,
        lng: -81.9,
        radius: 800,
      );
      final result = detectCurrentArea([forest, downtown], 29.2, -81.9);
      expect(result?.name, 'Historic Downtown Ocala');
    });

    test('an area actually containing the traveler beats a nearer-but-'
        'outside one', () {
      // Traveler at (29.2, -81.9).
      final containing = _area(
        id: '1',
        name: 'Contains Me',
        lat: 29.205, // ~555m north — but its radius comfortably covers that.
        lng: -81.9,
        radius: 1000,
      );
      final closerButOutside = _area(
        id: '2',
        name: 'Closer But Outside',
        lat: 29.2003, // ~33m north — closer in raw distance...
        lng: -81.9,
        radius: 10, // ...but its radius is too small to actually contain them.
      );
      final result =
          detectCurrentArea([containing, closerButOutside], 29.2, -81.9);
      expect(result?.name, 'Contains Me');
    });

    test('falls back to the nearest area within the fallback distance when '
        'outside all areas', () {
      final area = _area(
        id: '1',
        name: 'Silver Springs Area',
        lat: 29.22,
        lng: -82.05,
        radius: 500,
      );
      // ~1-2km away, outside the radius but within the 3km fallback.
      final result = detectCurrentArea([area], 29.21, -82.05);
      expect(result?.name, 'Silver Springs Area');
      expect(result?.isCurrentlyInside, isFalse);
    });

    test('returns null when nothing is within the fallback distance', () {
      final area = _area(
        id: '1',
        name: 'Far Away Area',
        lat: 29.2,
        lng: -82.0,
        radius: 100,
      );
      final result = detectCurrentArea([area], 40.0, -82.0); // continents away
      expect(result, isNull);
    });

    test('inactive or hidden areas are never detected', () {
      final inactive = _area(
        id: '1',
        name: 'Retired Area',
        lat: 29.2,
        lng: -82.0,
        radius: 5000,
        active: false,
      );
      final hidden = _area(
        id: '2',
        name: 'Hidden Area',
        lat: 29.2,
        lng: -82.0,
        radius: 5000,
        hidden: true,
      );
      final result = detectCurrentArea([inactive, hidden], 29.2, -82.0);
      expect(result, isNull);
    });

    test('non-area location types are ignored even if very close', () {
      final museum = MasterLocation.fromJson({
        'id': '1',
        'name': 'Some Museum',
        'category': 'museum',
        'latitude': 29.2,
        'longitude': -82.0,
        'trigger_radius': 5000,
      });
      final result = detectCurrentArea([museum], 29.2, -82.0);
      expect(result, isNull);
    });
  });

  group('DiscoveryArea computed fields', () {
    test('heroImageUrl is the first image, or null with no images', () {
      final withImages = DiscoveryArea(
        location: _area(
          id: '1',
          name: 'X',
          lat: 29.2,
          lng: -82.0,
          radius: 500,
          images: ['a.jpg', 'b.jpg'],
        ),
        distanceMeters: 0,
      );
      expect(withImages.heroImageUrl, 'a.jpg');

      final noImages = DiscoveryArea(
        location: _area(id: '2', name: 'Y', lat: 29.2, lng: -82.0, radius: 500),
        distanceMeters: 0,
      );
      expect(noImages.heroImageUrl, isNull);
    });

    test('estimatedListeningMinutes prefers the explicit admin value', () {
      final area = DiscoveryArea(
        location: _area(
          id: '1',
          name: 'X',
          lat: 29.2,
          lng: -82.0,
          radius: 500,
          estimatedListeningMinutes: 12,
          narrationScript: List.filled(1000, 'word').join(' '),
        ),
        distanceMeters: 0,
      );
      expect(area.estimatedListeningMinutes, 12);
    });

    test('estimatedListeningMinutes falls back to a word-count estimate', () {
      final area = DiscoveryArea(
        location: _area(
          id: '1',
          name: 'X',
          lat: 29.2,
          lng: -82.0,
          radius: 500,
          narrationScript: List.filled(300, 'word').join(' '), // ~2 min @150wpm
        ),
        distanceMeters: 0,
      );
      expect(area.estimatedListeningMinutes, 2);
    });

    test('estimatedListeningMinutes is 0 with no content at all', () {
      final area = DiscoveryArea(
        location: _area(id: '1', name: 'X', lat: 29.2, lng: -82.0, radius: 500),
        distanceMeters: 0,
      );
      expect(area.estimatedListeningMinutes, 0);
    });

    test('shortIntroduction prefers short_description, falls back to '
        'description', () {
      final withShort = DiscoveryArea(
        location: _area(
          id: '1',
          name: 'X',
          lat: 29.2,
          lng: -82.0,
          radius: 500,
          shortDescription: 'A lovely area.',
        ),
        distanceMeters: 0,
      );
      expect(withShort.shortIntroduction, 'A lovely area.');
    });
  });
}
