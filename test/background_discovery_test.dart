import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/services/announcement_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/background_discovery_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/gps_audio_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/history_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/services/queue_manager_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/story_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/user_preference_manager.dart';
import 'package:explorer_os_mobile/shared/models/narration.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

DiscoveryCandidate _c(
  String id,
  DiscoveryCategory cat, {
  double distance = 100,
  String? audioUrl = 'https://audio/$_placeholder.mp3',
  String? spokenText = 'A short fact.',
}) =>
    DiscoveryCandidate(
      id: id,
      category: cat,
      title: '$id (${cat.label})',
      distanceMeters: distance,
      audioUrl: audioUrl,
      spokenText: spokenText,
    );

const _placeholder = 'x';

void main() {
  group('discoveryCategoryFor', () {
    test('maps structured categories to the eight discovery topics', () {
      expect(discoveryCategoryFor('Wildlife Viewing'),
          DiscoveryCategory.wildlife);
      expect(discoveryCategoryFor('Wildflowers'), DiscoveryCategory.plants);
      expect(discoveryCategoryFor('Bird watching'), DiscoveryCategory.birds);
      expect(discoveryCategoryFor('Old-growth trees'),
          DiscoveryCategory.trees);
      expect(discoveryCategoryFor('Spring / geology'),
          DiscoveryCategory.geology);
      expect(discoveryCategoryFor('Historic Site'), DiscoveryCategory.history);
      expect(discoveryCategoryFor('Scenic Overlook'),
          DiscoveryCategory.hiddenGem);
      expect(discoveryCategoryFor('Did you know', name: 'fun fact'),
          DiscoveryCategory.interestingFact);
    });

    test('narrower categories win (birds over wildlife, trees over plants)', () {
      expect(discoveryCategoryFor('bird', subcategory: 'wildlife'),
          DiscoveryCategory.birds);
      expect(discoveryCategoryFor('oak tree', subcategory: 'plant'),
          DiscoveryCategory.trees);
    });

    test('returns null for non-environmental content', () {
      expect(discoveryCategoryFor('Parking'), isNull);
      expect(discoveryCategoryFor('Restrooms'), isNull);
      expect(discoveryCategoryFor(''), isNull);
      expect(discoveryCategoryFor(null), isNull);
    });
  });

  group('BackgroundDiscoveryScheduler.select (priority + distance + radius)', () {
    test('prefers the highest-priority category present', () {
      final s = BackgroundDiscoveryScheduler()
        ..updateNearby([
          _c('hist', DiscoveryCategory.history, distance: 50),
          _c('plant', DiscoveryCategory.plants, distance: 60),
          _c('animal', DiscoveryCategory.wildlife, distance: 400),
        ]);
      // Wildlife outranks plants and history even though it is farther away.
      expect(s.select()!.id, 'animal');
    });

    test('within a category, picks the nearest', () {
      final s = BackgroundDiscoveryScheduler()
        ..updateNearby([
          _c('far', DiscoveryCategory.birds, distance: 800),
          _c('near', DiscoveryCategory.birds, distance: 120),
        ]);
      expect(s.select()!.id, 'near');
    });

    test('excludes items beyond the radius', () {
      final s = BackgroundDiscoveryScheduler(radiusMeters: 500)
        ..updateNearby([_c('far', DiscoveryCategory.wildlife, distance: 900)]);
      expect(s.select(), isNull);
    });

    test('excludes items with nothing playable', () {
      final s = BackgroundDiscoveryScheduler()
        ..updateNearby([
          _c('empty', DiscoveryCategory.geology,
              audioUrl: null, spokenText: null),
        ]);
      expect(s.select(), isNull);
    });
  });

  group('BackgroundDiscoveryScheduler.due (quiet gap + anti-repeat)', () {
    test('stays silent until it has been quiet long enough', () {
      final s = BackgroundDiscoveryScheduler(quietGapSongs: 3)
        ..updateNearby([_c('a', DiscoveryCategory.wildlife)]);
      s.tick(); // 1
      expect(s.due(), isNull);
      s.tick(); // 2
      expect(s.due(), isNull);
      s.tick(); // 3
      expect(s.due(), isNotNull);
    });

    test('resets the gap after a narration plays', () {
      final s = BackgroundDiscoveryScheduler(quietGapSongs: 2)
        ..updateNearby([_c('a', DiscoveryCategory.wildlife)]);
      s.tick();
      s.tick();
      expect(s.isQuiet, isTrue);
      s.notifyNarration();
      expect(s.isQuiet, isFalse);
      expect(s.due(), isNull);
    });

    test('does not repeat a recently played item; moves to the next', () {
      final s = BackgroundDiscoveryScheduler(quietGapSongs: 1, cooldownPlays: 5)
        ..updateNearby([
          _c('deer', DiscoveryCategory.wildlife, distance: 100),
          _c('fox', DiscoveryCategory.wildlife, distance: 200),
        ]);
      s.tick();
      final first = s.due();
      expect(first, isNotNull);
      expect(first!.title, contains('deer'));
      expect(s.recentlyPlayed('deer'), isTrue);

      s.tick();
      final second = s.due();
      expect(second, isNotNull);
      expect(second!.title, contains('fox'),
          reason: 'the nearest fresh item is chosen, not the repeat');
    });

    test('emits recorded audio when present, else spoken text', () {
      final withAudio = BackgroundDiscoveryScheduler(quietGapSongs: 1)
        ..updateNearby([
          _c('a', DiscoveryCategory.history, audioUrl: 'https://a.mp3'),
        ]);
      withAudio.tick();
      final seg = withAudio.due()!;
      expect(seg.audioUrl, 'https://a.mp3');
      expect(seg.spokenText, isNull);
      expect(seg.type, AudioSegmentType.narration);
      expect(seg.tags, contains('history'));

      final spoken = BackgroundDiscoveryScheduler(quietGapSongs: 1)
        ..updateNearby([
          _c('b', DiscoveryCategory.plants,
              audioUrl: null, spokenText: 'Cypress trees love water.'),
        ]);
      spoken.tick();
      final seg2 = spoken.due()!;
      expect(seg2.audioUrl, isNull);
      expect(seg2.spokenText, 'Cypress trees love water.');
    });

    test('disabled engine never fires', () {
      final s = BackgroundDiscoveryScheduler(quietGapSongs: 1, enabled: false)
        ..updateNearby([_c('a', DiscoveryCategory.wildlife)]);
      s.tick();
      expect(s.due(), isNull);
    });

    test('fires nothing when no relevant content is nearby', () {
      final s = BackgroundDiscoveryScheduler(quietGapSongs: 1);
      s.tick();
      expect(s.due(), isNull);
    });
  });

  group('RadioEngineService integration', () {
    RadioEngineService buildEngine(BackgroundDiscoveryScheduler discovery) =>
        RadioEngineService(
          queue: QueueManagerService(),
          playback: PlaybackController(),
          station: StationManager(),
          stories: StoryScheduler(),
          announcements: AnnouncementScheduler(),
          gps: GPSAudioScheduler(),
          history: HistoryManager(),
          preferences: UserPreferenceManager(),
          discovery: discovery,
        );

    const station = RadioStation(id: 's1', name: 'Trail Radio');
    const playlist = [
      Song(id: '1', stationId: 's1', title: 'Song One', audioUrl: 'a1'),
      Song(id: '2', stationId: 's1', title: 'Song Two', audioUrl: 'a2'),
      Song(id: '3', stationId: 's1', title: 'Song Three', audioUrl: 'a3'),
    ];

    test('teaches nearby content between songs after a quiet gap', () {
      final discovery = BackgroundDiscoveryScheduler(quietGapSongs: 2)
        ..updateNearby([_c('gopher tortoise', DiscoveryCategory.wildlife)]);
      final engine = buildEngine(discovery);
      engine.djBanter.enabled = false; // isolate discovery from banter
      engine.station.load(station: station, playlist: playlist);

      engine.start(); // Song plays
      expect(engine.playback.current!.segment.type, AudioSegmentType.music);

      engine.onSegmentCompleted(); // gap 1 → still music
      expect(engine.playback.current!.segment.type, AudioSegmentType.music);

      engine.onSegmentCompleted(); // gap 2 → discovery narration inserted
      final current = engine.playback.current!.segment;
      expect(current.type, AudioSegmentType.narration);
      expect(current.title, contains('gopher tortoise'));
      expect(current.tags, contains('wildlife'));

      engine.onSegmentCompleted(); // narration ends → music resumes
      expect(engine.playback.current!.segment.type, AudioSegmentType.music);
    });

    test('a due story takes precedence over discovery', () {
      final discovery = BackgroundDiscoveryScheduler(quietGapSongs: 1)
        ..updateNearby([_c('deer', DiscoveryCategory.wildlife)]);
      final engine = buildEngine(discovery);
      engine.djBanter.enabled = false;
      engine.station.load(station: station, playlist: playlist);
      engine.stories.configure(
        everyTracks: 1,
        narrations: [
          AudioSegment.fromNarration(
            const Narration(id: 'n1', storyId: 'st1', title: 'Ranger Tale'),
          ),
        ],
      );

      engine.start();
      engine.onSegmentCompleted(); // story is due, not discovery
      expect(engine.playback.current!.segment.title, 'Ranger Tale');
    });
  });
}
