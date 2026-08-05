import 'package:explorer_os_mobile/features/admin/import/osm_overpass.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('query builds valid Overpass QL for a bbox', () {
    final q = OsmOverpass.query(
        south: 29.0, west: -82.3, north: 29.3, east: -82.0);
    expect(q, contains('[out:json]'));
    expect(q, contains('(29.0,-82.3,29.3,-82.0)'));
    expect(q, contains('out center tags;'));
    expect(q, contains('historic'));
    expect(q, contains('place~'));
  });

  test('parse maps OSM tags to LocationType and skips unnamed/uncoded', () {
    final json = {
      'elements': [
        // Node with a name + museum tag.
        {
          'type': 'node',
          'id': 1,
          'lat': 29.19,
          'lon': -82.13,
          'tags': {
            'name': 'Appleton Museum of Art',
            'tourism': 'museum',
            'website': 'https://appleton.org',
            'phone': '+1 352-291-4455',
            'opening_hours': 'Tu-Sa 10:00-17:00',
            'addr:housenumber': '4333',
            'addr:street': 'E Silver Springs Blvd',
            'addr:city': 'Ocala',
            'addr:state': 'FL',
          },
        },
        // Way with center + historic → historicSite.
        {
          'type': 'way',
          'id': 2,
          'center': {'lat': 29.18, 'lon': -82.14},
          'tags': {'name': 'Old Fort', 'historic': 'fort'},
        },
        // place=town → town.
        {
          'type': 'node',
          'id': 3,
          'lat': 29.05,
          'lon': -82.06,
          'tags': {'name': 'Belleview', 'place': 'town'},
        },
        // No name → skipped.
        {
          'type': 'node',
          'id': 4,
          'lat': 29.0,
          'lon': -82.0,
          'tags': {'tourism': 'museum'},
        },
        // No recognized tag → skipped.
        {
          'type': 'node',
          'id': 5,
          'lat': 29.0,
          'lon': -82.0,
          'tags': {'name': 'Random', 'random': 'thing'},
        },
        // No coordinate → skipped.
        {
          'type': 'way',
          'id': 6,
          'tags': {'name': 'No Coord Park', 'leisure': 'park'},
        },
      ],
    };

    final locs = OsmOverpass.parse(json, state: 'Florida', county: 'Marion');
    expect(locs.length, 3);

    final museum =
        locs.firstWhere((l) => l.name == 'Appleton Museum of Art');
    expect(museum.type, LocationType.museum);
    expect(museum.source, 'osm');
    expect(museum.sourceId, 'node/1');
    expect(museum.latitude, 29.19);
    expect(museum.longitude, -82.13);
    expect(museum.externalWebsite, 'https://appleton.org');
    expect(museum.phone, '+1 352-291-4455');
    expect(museum.hours, 'Tu-Sa 10:00-17:00');
    expect(museum.state, 'Florida');
    expect(museum.county, 'Marion');
    expect(museum.address, contains('4333 E Silver Springs Blvd'));
    expect(museum.contentStatus, ContentStatus.draft);

    expect(locs.firstWhere((l) => l.name == 'Old Fort').type,
        LocationType.historicSite);
    expect(locs.firstWhere((l) => l.name == 'Belleview').type,
        LocationType.town);
  });

  test('imported row carries provenance for dedupe', () {
    final json = {
      'elements': [
        {
          'type': 'node',
          'id': 99,
          'lat': 1.0,
          'lon': 2.0,
          'tags': {'name': 'Cafe X', 'amenity': 'cafe'},
        }
      ],
    };
    final loc = OsmOverpass.parse(json).single;
    expect(loc.type, LocationType.coffeeShop);
    expect(loc.source, 'osm');
    expect(loc.sourceId, 'node/99');
  });
}
