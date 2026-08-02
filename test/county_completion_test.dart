import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/locations/location_health.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

MasterLocation _loc({
  required String id,
  required String category,
  String? county,
  double? lat,
  double? lng,
  List<String> images = const [],
  List<String> audioFiles = const [],
  bool active = true,
  bool hidden = false,
}) =>
    MasterLocation.fromJson({
      'id': id,
      'name': id,
      'category': category,
      'county': county,
      'latitude': lat,
      'longitude': lng,
      'images': images,
      'audio_files': audioFiles,
      'active': active,
      'hidden': hidden,
    });

void main() {
  group('computeCountyCompletion', () {
    test('counts cities/communities/attractions scoped to one county', () {
      final all = [
        _loc(id: '1', category: 'city', county: 'Marion'),
        _loc(id: '2', category: 'community', county: 'Marion'),
        _loc(id: '3', category: 'attraction', county: 'Marion'),
        _loc(id: '4', category: 'attraction', county: 'Marion'),
        _loc(id: '5', category: 'city', county: 'Alachua'), // different county
      ];
      final c = computeCountyCompletion(all, county: 'Marion');
      expect(c.totalLocations, 4);
      expect(c.totalCities, 1);
      expect(c.totalCommunities, 1);
      expect(c.totalAttractions, 2);
    });

    test('county match is case-insensitive', () {
      final all = [_loc(id: '1', category: 'city', county: 'marion')];
      final c = computeCountyCompletion(all, county: 'Marion');
      expect(c.totalLocations, 1);
    });

    test('museums/parks/trails/hidden gems complete require the full '
        'hero+gallery+narration+gps+map checklist, not just matching type',
        () {
      final complete = _loc(
        id: '1',
        category: 'museum',
        county: 'Marion',
        lat: 29.2,
        lng: -82.1,
        images: ['a.jpg', 'b.jpg'],
        audioFiles: ['a.mp3'],
      );
      final incomplete = _loc(
        id: '2',
        category: 'museum',
        county: 'Marion',
        lat: 29.2,
        lng: -82.1,
        // no images, no audio -> not complete
      );
      final c = computeCountyCompletion([complete, incomplete],
          county: 'Marion');
      expect(c.museumsTotal, 2);
      expect(c.museumsComplete, 1);
    });

    test('parks groups state/national/county park types together', () {
      final all = [
        _loc(id: '1', category: 'state_park', county: 'Marion'),
        _loc(id: '2', category: 'national_park', county: 'Marion'),
        _loc(id: '3', category: 'county_park', county: 'Marion'),
        _loc(id: '4', category: 'museum', county: 'Marion'), // not a park
      ];
      final c = computeCountyCompletion(all, county: 'Marion');
      expect(c.parksTotal, 3);
    });

    test('trails groups trail + trailhead together', () {
      final all = [
        _loc(id: '1', category: 'trail', county: 'Marion'),
        _loc(id: '2', category: 'trailhead', county: 'Marion'),
      ];
      final c = computeCountyCompletion(all, county: 'Marion');
      expect(c.trailsTotal, 2);
    });

    test('narrations/images/GPS coverage counts', () {
      final all = [
        _loc(
          id: '1',
          category: 'attraction',
          county: 'Marion',
          lat: 29.2,
          lng: -82.1,
          images: ['a.jpg'],
          audioFiles: ['a.mp3'],
        ),
        _loc(id: '2', category: 'attraction', county: 'Marion'), // bare
      ];
      final c = computeCountyCompletion(all, county: 'Marion');
      expect(c.narrationsComplete, 1);
      expect(c.imagesComplete, 1);
      expect(c.gpsVerified, 1);
    });

    test('overall completion percent averages the per-location checklist', () {
      final full = _loc(
        id: '1',
        category: 'attraction',
        county: 'Marion',
        lat: 29.2,
        lng: -82.1,
        images: ['a.jpg', 'b.jpg'],
        audioFiles: ['a.mp3'],
      ); // 5/5 = 100%
      final bare = _loc(id: '2', category: 'attraction', county: 'Marion');
      // bare: gps=false, hero=false, gallery=false, narration=false,
      // map=true (active && !hidden) -> 1/5 = 20%
      final c = computeCountyCompletion([full, bare], county: 'Marion');
      expect(c.overallCompletionPercent, 60); // average of 100 and 20
    });

    test('empty county yields all zeros, no division-by-zero errors', () {
      final c = computeCountyCompletion(const [], county: 'Nowhere');
      expect(c.totalLocations, 0);
      expect(c.overallCompletionPercent, 0);
    });
  });

  group('computeCountyCompletions', () {
    test('groups by distinct county, sorted alphabetically', () {
      final all = [
        _loc(id: '1', category: 'city', county: 'Marion'),
        _loc(id: '2', category: 'city', county: 'Alachua'),
        _loc(id: '3', category: 'city', county: null), // excluded
      ];
      final all2 = computeCountyCompletions(all);
      expect(all2.map((c) => c.county), ['Alachua', 'Marion']);
    });

    test('duplicate-cased county names are merged into one entry', () {
      final all = [
        _loc(id: '1', category: 'city', county: 'Marion'),
        _loc(id: '2', category: 'city', county: 'MARION'),
      ];
      final all2 = computeCountyCompletions(all);
      expect(all2, hasLength(1));
      expect(all2.first.totalLocations, 2);
    });
  });
}
