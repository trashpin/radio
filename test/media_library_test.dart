import 'package:explorer_os_mobile/features/locations/location_health.dart';
import 'package:explorer_os_mobile/features/locations/media_match.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter_test/flutter_test.dart';

MasterLocation _loc(
  String name, {
  List<String> images = const [],
  List<String> audio = const [],
  double? lat = 29.0,
  bool active = true,
  bool hidden = false,
}) =>
    MasterLocation(
      id: name,
      name: name,
      type: LocationType.lake,
      latitude: lat,
      longitude: -82.0,
      images: images,
      audioFiles: audio,
      active: active,
      hidden: hidden,
    );

void main() {
  group('completionFor', () {
    test('100% when hero + gallery + narration + gps + map', () {
      final c = completionFor(_loc('Lake Bryant',
          images: ['a.jpg', 'b.jpg'], audio: ['n.mp3']));
      expect(c.hero, isTrue);
      expect(c.gallery, isTrue);
      expect(c.narration, isTrue);
      expect(c.gps, isTrue);
      expect(c.map, isTrue);
      expect(c.percent, 100);
      expect(c.complete, isTrue);
    });

    test('80% when gallery is missing', () {
      final c = completionFor(
          _loc('Juniper Springs', images: ['hero.jpg'], audio: ['n.mp3']));
      expect(c.hero, isTrue);
      expect(c.gallery, isFalse);
      expect(c.percent, 80);
    });

    test('hidden location is not "on map"', () {
      final c = completionFor(_loc('X',
          images: ['a.jpg', 'b.jpg'], audio: ['n.mp3'], hidden: true));
      expect(c.map, isFalse);
      expect(c.percent, 80);
    });
  });

  group('computeImageHealth', () {
    test('aggregates hero/gallery/broken/duplicate/unassigned', () {
      final all = [
        _loc('A', images: ['https://x/1.jpg', 'https://x/2.jpg']),
        _loc('B', images: ['https://x/1.jpg']), // dup of A's first + no gallery
        _loc('C'), // missing hero (unassigned)
        _loc('D', images: ['ftp://bad']), // broken
        _loc('E', images: ['https://x/9.jpg'], hidden: true), // not visible
      ];
      final h = computeImageHealth(all);
      expect(h.totalImages, 5);
      expect(h.missingHero, 1); // C
      expect(h.withHero, 3); // A, B, D (E hidden)
      expect(h.brokenImageLinks, 1); // D
      expect(h.duplicateImages, 1); // shared https://x/1.jpg
    });
  });

  group('matchMediaToLocation', () {
    final locs = [
      _loc('Lake Bryant'),
      _loc('Silver Springs'),
      _loc('Lake Bryant Road'),
    ];
    test('matches hero filename to the location, flags hero', () {
      final m = matchMediaToLocation('lake_bryant_hero.jpg', locs);
      expect(m.location?.name, 'Lake Bryant');
      expect(m.isHero, isTrue);
    });
    test('matches gallery filename without hero flag', () {
      final m = matchMediaToLocation('Silver Springs 1200x800.png', locs);
      expect(m.location?.name, 'Silver Springs');
      expect(m.isHero, isFalse);
    });
    test('no match → unassigned', () {
      final m = matchMediaToLocation('random_photo_47.jpg', locs);
      expect(m.matched, isFalse);
    });
  });
}
