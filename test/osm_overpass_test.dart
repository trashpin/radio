import 'package:explorer_os_mobile/features/admin/import/osm_overpass.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('query builds Overpass QL scoped to the active tiers only', () {
    final q = OsmOverpass.query(
        south: 29.0, west: -82.3, north: 29.3, east: -82.0);
    expect(q, contains('[out:json]'));
    expect(q, contains('(29.0,-82.3,29.3,-82.0)'));
    expect(q, contains('out center tags;'));
    expect(q, contains('place~'));
    expect(q, contains('leisure~"park'));
    expect(q, contains('natural~"spring"'));
    // Businesses / other categories are no longer queried.
    expect(q, isNot(contains('amenity')));
    expect(q, isNot(contains('historic')));
    expect(q, isNot(contains('museum')));
  });

  test('parse keeps only active tiers (city/community, city park, spring)', () {
    final json = {
      'elements': [
        // place=town → town (city tier) — kept.
        {
          'type': 'node', 'id': 3, 'lat': 29.05, 'lon': -82.06,
          'tags': {'name': 'Belleview', 'place': 'town'},
        },
        // leisure=park → cityPark — kept.
        {
          'type': 'way', 'id': 7, 'center': {'lat': 29.19, 'lon': -82.14},
          'tags': {'name': 'Tuscawilla Park', 'leisure': 'park'},
        },
        // natural=spring → spring — kept.
        {
          'type': 'node', 'id': 8, 'lat': 29.21, 'lon': -82.05,
          'tags': {'name': 'Silver Springs', 'natural': 'spring'},
        },
        // Inactive types — must be DROPPED even if tagged/named.
        {
          'type': 'node', 'id': 1, 'lat': 29.19, 'lon': -82.13,
          'tags': {'name': 'Appleton Museum', 'tourism': 'museum'},
        },
        {
          'type': 'node', 'id': 9, 'lat': 29.19, 'lon': -82.13,
          'tags': {'name': 'Corner Cafe', 'amenity': 'cafe'},
        },
        {
          'type': 'way', 'id': 2, 'center': {'lat': 29.18, 'lon': -82.14},
          'tags': {'name': 'Old Fort', 'historic': 'fort'},
        },
      ],
    };

    final locs = OsmOverpass.parse(json, state: 'Florida', county: 'Marion');
    final byName = {for (final l in locs) l.name: l.type};
    expect(byName.keys.toSet(),
        {'Belleview', 'Tuscawilla Park', 'Silver Springs', 'Appleton Museum'});
    expect(byName['Belleview'], LocationType.town);
    expect(byName['Tuscawilla Park'], LocationType.cityPark);
    expect(byName['Silver Springs'], LocationType.spring);
    // Museum is now an active tier (see active_location_types.dart) — kept,
    // not dropped, when tagged data reaches parse().
    expect(byName['Appleton Museum'], LocationType.museum);
    // Still-inactive types excluded entirely.
    expect(byName.containsKey('Corner Cafe'), isFalse);
    expect(byName.containsKey('Old Fort'), isFalse);
  });

  test('imported row carries provenance for dedupe', () {
    final json = {
      'elements': [
        {
          'type': 'node', 'id': 8, 'lat': 29.21, 'lon': -82.05,
          'tags': {'name': 'Silver Springs', 'natural': 'spring'},
        }
      ],
    };
    final loc = OsmOverpass.parse(json).single;
    expect(loc.type, LocationType.spring);
    expect(loc.source, 'osm');
    expect(loc.sourceId, 'node/8');
    expect(loc.contentStatus, ContentStatus.draft);
  });
}
