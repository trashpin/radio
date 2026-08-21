import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/what_is_that/services/what_is_that_search.dart';
import 'package:flutter_test/flutter_test.dart';

// Ocala, FL-ish origin. One degree of longitude here is ~54 miles, one
// degree of latitude ~69 miles — plenty of separation for cone/radius tests
// without needing precise geodesy.
final _origin = GPSLocation(
  latitude: 29.0,
  longitude: -82.0,
  timestamp: DateTime(2026, 1, 1),
);

MasterLocation _loc(
  String id,
  String name, {
  LocationType type = LocationType.attraction,
  required double latitude,
  required double longitude,
  List<String> images = const [],
  String? description,
  List<String> audioFiles = const [],
  bool active = true,
  bool hidden = false,
  bool featured = false,
  int priority = 0,
}) =>
    MasterLocation(
      id: id,
      name: name,
      type: type,
      latitude: latitude,
      longitude: longitude,
      images: images,
      description: description,
      audioFiles: audioFiles,
      featured: featured,
      priority: priority,
      active: active,
      hidden: hidden,
    );

void main() {
  group('findWhatIsThatCandidates', () {
    test('finds a location within the cone directly ahead (due north)', () {
      final locations = [
        _loc('a', 'Silver Springs', latitude: 29.05, longitude: -82.0),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0, // facing north
      );
      expect(result.map((c) => c.locationId), ['a']);
      expect(result.single.name, 'Silver Springs');
    });

    test('excludes a location outside the cone (behind the user)', () {
      final locations = [
        _loc('behind', 'Something Behind Me',
            latitude: 28.95, longitude: -82.0), // due south
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0, // facing north
      );
      expect(result, isEmpty);
    });

    test('excludes a location beyond the search radius', () {
      final locations = [
        _loc('far', 'Way Out There', latitude: 30.5, longitude: -82.0),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0,
        radiusMeters: 8046.72, // 5 miles — ~104mi away, well beyond
      );
      expect(result, isEmpty);
    });

    test('excludes only the small block-list of pure-utility/diffuse-region '
        'types — everything else in the shared taxonomy is eligible', () {
      final locations = [
        _loc('gas', 'Some Gas Station',
            type: LocationType.gasStation, latitude: 29.05, longitude: -82.0),
        _loc('parking', 'A Parking Lot',
            type: LocationType.parking, latitude: 29.05, longitude: -82.0),
        _loc('park', 'A State Park',
            type: LocationType.statePark, latitude: 29.05, longitude: -82.0),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0,
      );
      expect(result.map((c) => c.locationId), ['park']);
    });

    test('SEARCH MORE TYPES OF THINGS: buildings/structures and natural '
        'features across the taxonomy are all found by the SAME unified '
        'search — no per-category search system', () {
      final locations = [
        _loc('bridge', 'Old Bridge',
            type: LocationType.bridge, latitude: 29.01, longitude: -82.0),
        _loc('museum', 'Local Museum',
            type: LocationType.museum, latitude: 29.02, longitude: -82.0),
        _loc('monument', 'War Monument',
            type: LocationType.monument, latitude: 29.03, longitude: -82.0),
        _loc('cave', 'Limestone Cave',
            type: LocationType.cave, latitude: 29.04, longitude: -82.0),
        _loc('wma', 'Wildlife Management Area',
            type: LocationType.wildlifeManagementArea,
            latitude: 29.05,
            longitude: -82.0),
        _loc('overlook', 'Scenic Overlook',
            type: LocationType.scenicOverlook,
            latitude: 29.06,
            longitude: -82.0),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0,
        limit: 10,
      );
      expect(
        result.map((c) => c.locationId).toSet(),
        {'bridge', 'museum', 'monument', 'cave', 'wma', 'overlook'},
      );
    });

    test('excludes diffuse administrative regions with no single '
        'point-at-able spot (county/state/country/neighborhood/area)', () {
      final locations = [
        _loc('county', 'Some County',
            type: LocationType.county, latitude: 29.02, longitude: -82.0),
        _loc('neighborhood', 'Some Neighborhood',
            type: LocationType.neighborhood,
            latitude: 29.02,
            longitude: -82.0),
        _loc('town', 'A Real Town',
            type: LocationType.town, latitude: 29.02, longitude: -82.0),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0,
      );
      expect(result.map((c) => c.locationId), ['town']);
    });

    test('defaults to the "best 2-3 choices" limit of 3, not the whole cone',
        () {
      final locations = [
        for (var i = 1; i <= 8; i++)
          _loc('p$i', 'Place $i', latitude: 29.0 + i * 0.01, longitude: -82.0),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0,
      );
      expect(result.length, 3);
    });

    test('LOCATION RELEVANCE: a featured/high-priority place can outrank a '
        'slightly closer, unremarkable one', () {
      final locations = [
        _loc('plain', 'Unremarkable Spot', latitude: 29.010, longitude: -82.0),
        _loc('featured', 'Well-Known Landmark',
            latitude: 29.011, longitude: -82.0, featured: true),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0,
        limit: 2,
      );
      expect(result.first.locationId, 'featured',
          reason: 'featured landmark wins the top slot despite being '
              'marginally farther');
    });

    test('LOCATION RELEVANCE: a much closer plain place still beats a '
        'far-away featured one — relevance only breaks close ties, it '
        'never overrides real distance', () {
      final locations = [
        _loc('near', 'Right Here', latitude: 29.002, longitude: -82.0),
        _loc('far-featured', 'Distant Landmark',
            latitude: 29.06, longitude: -82.0, featured: true),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0,
        limit: 2,
      );
      expect(result.first.locationId, 'near');
    });

    test('excludes inactive and hidden locations', () {
      final locations = [
        _loc('inactive', 'Closed Place',
            latitude: 29.05, longitude: -82.0, active: false),
        _loc('hidden', 'Secret Place',
            latitude: 29.05, longitude: -82.0, hidden: true),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0,
      );
      expect(result, isEmpty);
    });

    test('ranks nearest first and respects the limit', () {
      final locations = [
        for (var i = 1; i <= 4; i++)
          _loc('p$i', 'Place $i', latitude: 29.0 + i * 0.02, longitude: -82.0),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0,
        limit: 2,
      );
      expect(result.length, 2);
      expect(result.map((c) => c.locationId), ['p1', 'p2']);
    });

    test('carries image/description/audio through from the location record — '
        'never invents any of it', () {
      final locations = [
        _loc('a', 'Silver Springs',
            latitude: 29.02,
            longitude: -82.0,
            images: ['https://img/springs.jpg'],
            description: 'A famous spring.',
            audioFiles: ['https://audio/springs.mp3']),
        _loc('b', 'Bare Location', latitude: 29.03, longitude: -82.0),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0,
      );
      final a = result.firstWhere((c) => c.locationId == 'a');
      expect(a.imageUrl, 'https://img/springs.jpg');
      expect(a.description, 'A famous spring.');
      expect(a.audioUrl, 'https://audio/springs.mp3');
      expect(a.hasAudio, isTrue);

      final b = result.firstWhere((c) => c.locationId == 'b');
      expect(b.imageUrl, isNull);
      expect(b.audioUrl, isNull);
      expect(b.hasAudio, isFalse);
    });

    test('distanceLabel formats miles the same way the rest of the radio UI '
        'does', () {
      final locations = [
        _loc('near', 'Near Place', latitude: 29.01, longitude: -82.0),
      ];
      final result = findWhatIsThatCandidates(
        locations: locations,
        userLocation: _origin,
        headingDegrees: 0,
      );
      expect(result.single.distanceLabel, endsWith(' mi'));
    });

    test('an empty location list produces no candidates, never throws', () {
      final result = findWhatIsThatCandidates(
        locations: const [],
        userLocation: _origin,
        headingDegrees: 0,
      );
      expect(result, isEmpty);
    });
  });
}
