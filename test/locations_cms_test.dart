import 'package:explorer_os_mobile/features/locations/location_health.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MasterLocation parses + writes the richer PoI fields', () {
    final l = MasterLocation.fromJson({
      'id': '1',
      'name': 'Silver Springs',
      'category': 'spring',
      'state': 'Florida',
      'county': 'Marion',
      'city': 'Silver Springs',
      'latitude': 29.21,
      'longitude': -82.05,
      'trigger_radius': 400,
      'address': '5656 E Silver Springs Blvd',
      'short_description': 'Glass-bottom boats + crystal springs.',
      'long_description': 'A long, rich description of the springs…',
      'narration_script': 'Welcome to Silver Springs…',
      'hours': '8am–sunset',
      'admission': '\$8 per vehicle',
      'external_website': 'https://example.com',
      'parking_info': 'Free lot',
      'restrooms': 'Yes',
      'difficulty': 'Easy',
      'tags': ['boat', 'family', 'springs'],
      'family_friendly': true,
      'pet_friendly': false,
      'wheelchair_accessible': true,
      'active': true,
    });
    expect(l.state, 'Florida');
    expect(l.shortDescription, startsWith('Glass-bottom'));
    expect(l.longDescription, contains('rich description'));
    expect(l.narrationScript, startsWith('Welcome'));
    expect(l.hours, '8am–sunset');
    expect(l.tags, ['boat', 'family', 'springs']);
    expect(l.familyFriendly, isTrue);
    expect(l.petFriendly, isFalse);
    expect(l.wheelchairAccessible, isTrue);
    expect(l.bestDescription, contains('rich description')); // long wins

    final w = l.toWrite();
    expect(w['state'], 'Florida');
    expect(w['short_description'], l.shortDescription);
    expect(w['long_description'], l.longDescription);
    expect(w['narration_script'], l.narrationScript);
    expect(w['tags'], ['boat', 'family', 'springs']);
    expect(w['wheelchair_accessible'], true);
  });

  test('bestDescription falls back long → description → short', () {
    MasterLocation g({String? long, String? desc, String? short}) =>
        MasterLocation(
          id: 'x',
          name: 'X',
          type: LocationType.attraction,
          longDescription: long,
          description: desc,
          shortDescription: short,
        );
    expect(g(long: 'L', desc: 'D', short: 'S').bestDescription, 'L');
    expect(g(desc: 'D', short: 'S').bestDescription, 'D');
    expect(g(short: 'S').bestDescription, 'S');
    expect(g().bestDescription, isNull);
  });

  group('locationIsMissing', () {
    MasterLocation g({
      double? lat,
      List<String> images = const [],
      List<String> audio = const [],
      String? script,
      String? desc,
      bool active = true,
      bool hidden = false,
    }) => MasterLocation(
      id: 'x',
      name: 'X',
      type: LocationType.museum,
      latitude: lat,
      longitude: lat == null ? null : -82.0,
      images: images,
      audioFiles: audio,
      narrationScript: script,
      description: desc,
      active: active,
      hidden: hidden,
    );

    test('gps missing when no coordinates', () {
      expect(locationIsMissing(g(), MissingContent.gps), isTrue);
      expect(locationIsMissing(g(lat: 29.2), MissingContent.gps), isFalse);
    });

    test('images/description/narration missing for active empty location', () {
      final empty = g(lat: 29.2);
      expect(locationIsMissing(empty, MissingContent.images), isTrue);
      expect(locationIsMissing(empty, MissingContent.description), isTrue);
      expect(locationIsMissing(empty, MissingContent.narration), isTrue);
    });

    test('narration satisfied by audio OR a script', () {
      expect(
        locationIsMissing(
          g(lat: 29.2, audio: ['https://a.mp3']),
          MissingContent.narration,
        ),
        isFalse,
      );
      expect(
        locationIsMissing(
          g(lat: 29.2, script: 'hello'),
          MissingContent.narration,
        ),
        isFalse,
      );
    });

    test('disabled locations are excluded from content facets', () {
      final disabled = g(active: false);
      expect(locationIsMissing(disabled, MissingContent.images), isFalse);
      expect(locationIsMissing(disabled, MissingContent.description), isFalse);
      // gps still reported regardless of status
      expect(locationIsMissing(disabled, MissingContent.gps), isTrue);
    });
  });

  test('computeLocationHealth counts the new missing facets', () {
    final all = [
      MasterLocation(
        id: '1',
        name: 'Complete',
        type: LocationType.spring,
        latitude: 29.2,
        longitude: -82.0,
        images: const ['https://i.jpg'],
        audioFiles: const ['https://a.mp3'],
        longDescription: 'desc',
      ),
      MasterLocation(
        id: '2',
        name: 'Bare',
        type: LocationType.trail,
        latitude: 29.3,
        longitude: -82.1,
      ),
    ];
    final h = computeLocationHealth(all);
    expect(h.total, 2);
    expect(h.missingImages, 1);
    expect(h.missingDescription, 1);
    expect(h.missingNarration, 1);
  });
}
