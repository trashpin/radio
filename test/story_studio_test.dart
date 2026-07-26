import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/story_studio/models/story_category.dart';
import 'package:explorer_os_mobile/features/story_studio/models/story_entry.dart';
import 'package:explorer_os_mobile/features/story_studio/services/gps_story_selector.dart';
import 'package:explorer_os_mobile/features/story_studio/services/story_composer.dart';

StoryEntry story(
  String id, {
  double lat = 29.18,
  double lng = -81.71,
  int radius = 150,
  bool published = true,
  bool audio = true,
  bool coords = true,
  StoryCategory category = StoryCategory.springs,
  String? parkId,
}) =>
    StoryEntry(
      id: id,
      title: id,
      category: category,
      parkId: parkId,
      latitude: coords ? lat : null,
      longitude: coords ? lng : null,
      triggerRadiusM: radius,
      audioUrl: audio ? 'https://cdn/$id.mp3' : null,
      published: published,
    );

void main() {
  group('StoryCategory', () {
    test('has the full expandable set and round-trips', () {
      expect(StoryCategory.values.length, 26);
      expect(StoryCategory.fromDb('SPRINGS'), StoryCategory.springs);
      expect(StoryCategory.fromDb('NIGHT_SKY'), StoryCategory.nightSky);
      expect(StoryCategory.fromDb('???'), StoryCategory.parkHistory);
    });
  });

  group('StoryComposer', () {
    test('composes a filled, interpreter-style story (no placeholders)', () {
      final c = StoryComposer(rng: Random(1));
      final text = c.compose(
          location: 'Silver Glen Springs', category: StoryCategory.springs);
      expect(text.contains('{'), isFalse);
      expect(text.contains('Silver Glen Springs'), isTrue);
      expect(text.split(' ').length, greaterThan(20));
    });

    test('generateVariations returns N drafts with distinct variation styles',
        () {
      final c = StoryComposer(rng: Random(2));
      final v = c.generateVariations(
          location: 'Juniper Springs', category: StoryCategory.wildlife, count: 5);
      expect(v, hasLength(5));
      expect(v.map((e) => e.variation).toSet().length, 5); // 5 distinct styles
      expect(v.every((e) => e.title.contains('Juniper Springs')), isTrue);
      expect(v.every((e) => !e.transcript.contains('{')), isTrue);
    });
  });

  group('GpsStorySelector', () {
    final sel = GpsStorySelector(rng: Random(3));

    test('only returns playable stories within their trigger radius', () {
      final stories = [
        story('near', lat: 29.180, lng: -81.710, radius: 200),
        story('far', lat: 29.500, lng: -81.900), // kilometers away
        story('draft', published: false),
        story('noaudio', audio: false),
      ];
      final hit = sel.select(stories, 29.1801, -81.7101);
      expect(hit, isNotNull);
      expect(hit!.id, 'near');
    });

    test('avoids already-played stories unless none remain', () {
      final stories = [
        story('a', lat: 29.180, lng: -81.710),
        story('b', lat: 29.180, lng: -81.710),
      ];
      // 'a' already played → should pick 'b'.
      final hit = sel.select(stories, 29.180, -81.710, alreadyPlayed: {'a'});
      expect(hit!.id, 'b');
      // both played → falls back to any eligible (not null).
      final hit2 =
          sel.select(stories, 29.180, -81.710, alreadyPlayed: {'a', 'b'});
      expect(hit2, isNotNull);
    });

    test('returns null when nothing is in range', () {
      final stories = [story('far', lat: 30.0, lng: -82.0)];
      expect(sel.select(stories, 29.18, -81.71), isNull);
    });

    test('filters by category and park', () {
      final stories = [
        story('spring', category: StoryCategory.springs, parkId: 'ocala'),
        story('trail', category: StoryCategory.trails, parkId: 'ocala'),
      ];
      final hit = sel.select(stories, 29.18, -81.71,
          category: StoryCategory.trails, parkId: 'ocala');
      expect(hit!.id, 'trail');
    });
  });

  test('StoryEntry.fromJson + playable flag', () {
    final s = StoryEntry.fromJson({
      'id': '1',
      'title': 'Springs history',
      'category': 'SPRINGS',
      'latitude': 29.18,
      'longitude': -81.71,
      'trigger_radius_m': 120,
      'audio_url': 'https://cdn/1.mp3',
      'published': true,
      'status': 'completed',
    });
    expect(s.playable, isTrue);
    expect(s.triggerRadiusM, 120);
    expect(s.status, StoryStatus.completed);
    expect(s.toInsert()['category'], 'SPRINGS');
  });
}
