import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart';
import 'package:explorer_os_mobile/features/locations/data/location_narration.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter_test/flutter_test.dart';

double _lat(double miles) => 29.0 + miles * 1609.344 / 111320.0;
const double _lng = -82.0;

MasterLocation _loc(
  String name,
  LocationType type, {
  double miles = 0,
  List<String> audio = const [],
  String? desc,
}) =>
    MasterLocation(
      id: name,
      name: name,
      type: type,
      latitude: _lat(miles),
      longitude: _lng,
      description: desc,
      audioFiles: audio,
    );

ContentItem _content(
  String title,
  ContentCategory cat, {
  double miles = 0,
  String? audio,
  String? text,
}) =>
    ContentItem(
      id: 'c_$title',
      title: title,
      category: cat,
      latitude: _lat(miles),
      longitude: _lng,
      audioUrl: audio,
      text: text,
    );

void main() {
  group('relevantCategories', () {
    test('maps location types to their narration categories', () {
      expect(relevantCategories(LocationType.county),
          contains(ContentCategory.countyWelcome));
      expect(relevantCategories(LocationType.river),
          contains(ContentCategory.riverStory));
      expect(relevantCategories(LocationType.statePark),
          contains(ContentCategory.parkStory));
      expect(relevantCategories(LocationType.historicSite),
          contains(ContentCategory.history));
    });
  });

  group('resolveLocationNarration', () {
    test('prefers the location\'s own recorded audio', () {
      final loc = _loc('Silver Springs', LocationType.spring,
          audio: ['http://x/ss.mp3'], desc: 'Crystal clear water.');
      final n = resolveLocationNarration(loc, const []);
      expect(n.hasAudio, isTrue);
      expect(n.audioUrl, 'http://x/ss.mp3');
      expect(n.title, 'Silver Springs');
    });

    test('attaches nearest matching location_content (audio wins)', () {
      final loc = _loc('Juniper Springs', LocationType.spring);
      final content = [
        _content('Juniper Springs', ContentCategory.water,
            miles: 0.2, audio: 'http://x/js.mp3', text: 'A spring run.'),
        _content('Faraway Lake', ContentCategory.lakeStory,
            miles: 10, audio: 'http://x/far.mp3'),
      ];
      final n = resolveLocationNarration(loc, content);
      expect(n.audioUrl, 'http://x/js.mp3');
      expect(n.sourceContentId, 'c_Juniper Springs');
      expect(n.text, 'A spring run.');
    });

    test('ignores content beyond the radius', () {
      final loc = _loc('Lake Bryant', LocationType.lake);
      final content = [
        _content('Lake Bryant', ContentCategory.lakeStory,
            miles: 5, audio: 'http://x/lb.mp3'),
      ];
      final n = resolveLocationNarration(loc, content, radiusMeters: 1609.344);
      expect(n.hasAudio, isFalse); // 5 miles > 1 mile radius
      expect(n.sourceContentId, isNull);
    });

    test('falls back to a composed script when nothing matches', () {
      final loc = _loc('Mystery Overlook', LocationType.scenicOverlook,
          desc: 'A sweeping view of the valley.');
      final n = resolveLocationNarration(loc, const []);
      expect(n.hasAudio, isFalse);
      expect(n.text, 'A sweeping view of the valley.');
    });

    test('composed script uses type + place when no description', () {
      final loc = MasterLocation(
        id: 'x',
        name: 'Fort King',
        type: LocationType.historicSite,
        latitude: 1,
        longitude: 1,
        county: 'Marion',
        city: 'Ocala',
      );
      final n = resolveLocationNarration(loc, const []);
      expect(n.text, contains('Fort King'));
      expect(n.text.toLowerCase(), contains('historic site'));
    });
  });
}
