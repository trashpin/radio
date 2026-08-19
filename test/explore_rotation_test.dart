import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/services/announcement_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/background_discovery_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/explore_rotation_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/gps_audio_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/history_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/playback_controller.dart';
import 'package:explorer_os_mobile/features/radio/services/queue_manager_service.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';
import 'package:explorer_os_mobile/features/radio/services/station_manager.dart';
import 'package:explorer_os_mobile/features/radio/services/story_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/user_preference_manager.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';
import 'package:flutter_test/flutter_test.dart';

ExploreCandidate _c(
  String id,
  ExploreCategory cat, {
  String? audioUrl,
  String? spokenText = 'A short fact.',
}) =>
    ExploreCandidate(
      id: id,
      category: cat,
      title: '$id (${cat.label})',
      audioUrl: audioUrl,
      spokenText: spokenText,
    );

void main() {
  group('ExploreRotationScheduler.select (fixed tier order, skip-if-empty)', () {
    test('tier 1 WHAT\'S AHEAD beats every other tier', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
          ExploreCategory.history: [_c('b', ExploreCategory.history)],
        });
      expect(s.select()!.id, 'a');
    });

    test('tier 2 WILDLIFE/NATURE beats tier 3 WHERE YOU ARE — the actual '
        'behavior change from the old enum-order rotation', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.wildlife: [_c('w', ExploreCategory.wildlife)],
          ExploreCategory.whereYouAre: [_c('y', ExploreCategory.whereYouAre)],
          ExploreCategory.history: [_c('h', ExploreCategory.history)],
        });
      expect(s.select()!.id, 'w');
    });

    test('within tier 3, WHERE YOU ARE beats the broader COUNTY fallback', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [_c('y', ExploreCategory.whereYouAre)],
          ExploreCategory.county: [_c('c', ExploreCategory.county)],
        });
      expect(s.select()!.id, 'y');
    });

    test('skips a category with no usable content and moves to the next', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: const [],
          ExploreCategory.whereYouAre: const [],
          ExploreCategory.county: [_c('marion-fact', ExploreCategory.county)],
        });
      expect(s.select()!.id, 'marion-fact');
    });

    test('a candidate with neither audio nor spoken text never fills a slot', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.wildlife: [
            _c('empty', ExploreCategory.wildlife, spokenText: null),
          ],
          ExploreCategory.history: [_c('h', ExploreCategory.history)],
        });
      expect(s.select()!.id, 'h');
    });

    test('nothing anywhere → null (caller falls back to music)', () {
      final s = ExploreRotationScheduler();
      expect(s.select(), isNull);
      expect(s.due(), isNull);
    });
  });

  group('ExploreRotationScheduler.due (tier re-checked every call, anti-repeat)', () {
    test('WHAT\'S AHEAD is re-checked on EVERY call, not once per lap — the '
        'direct regression test for the old "1 turn in 8" cursor bug', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [
            _c('headed-1', ExploreCategory.whereHeaded),
            _c('headed-2', ExploreCategory.whereHeaded),
          ],
        });
      expect(s.due()!.id, contains('headed'));
      // Still WHAT'S AHEAD, not skipped to a lower tier just because one
      // ahead item already aired this call.
      expect(s.due()!.id, contains('headed'));
    });

    test('does not repeat a played item; prefers another unused item in the '
        'same category', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.wildlife: [
            _c('black-bear', ExploreCategory.wildlife),
            _c('alligator', ExploreCategory.wildlife),
          ],
        });
      final first = s.due();
      expect(first!.id, contains('black-bear'));
      expect(s.hasPlayed(ExploreCategory.wildlife, 'black-bear'), isTrue);

      final second = s.due();
      expect(second!.id, contains('alligator'),
          reason: 'black-bear already aired; the other wildlife item plays');
    });

    test('a non-sticky category with only one candidate repeats it once the '
        'pool is exhausted, rather than going quiet (literal "don\'t repeat '
        'while other unused content exists" — there is no other content)', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.history: [_c('only', ExploreCategory.history)],
        });
      expect(s.due()!.id, contains('only'));
      expect(s.due()!.id, contains('only'),
          reason: 'the whole (one-item) pool was exhausted, so it resets');
    });

    test('a full non-sticky category (3 items) plays each exactly once, then '
        'resets and repeats the first — CONTENT POOL RESET only once '
        'genuinely exhausted, never prematurely', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.history: [
            _c('h1', ExploreCategory.history),
            _c('h2', ExploreCategory.history),
            _c('h3', ExploreCategory.history),
          ],
        });
      final ids = [s.due()!.id, s.due()!.id, s.due()!.id];
      expect(ids.map((i) => i.contains('h1') ? 'h1' : i.contains('h2') ? 'h2' : 'h3'),
          containsAll(['h1', 'h2', 'h3']));
      expect(s.due()!.id, contains('h1'),
          reason: 'pool exhausted after 3 plays; resets and repeats the first');
    });

    test('a STICKY category (whereHeaded) does NOT reset — once its single '
        'item has aired, it stays quiet rather than re-triggering while '
        'still being approached', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      expect(s.due()!.id, contains('a'));
      expect(s.due(), isNull,
          reason: 'whereHeaded is sticky — exhausted, but must not reset');
    });

    test('emits recorded audio when present, else spoken text, and carries '
        'the tellMeMoreContext through', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.geology: [
            _c('aquifer', ExploreCategory.geology, audioUrl: 'https://a.mp3'),
          ],
        });
      final seg = s.due()!;
      expect(seg.audioUrl, 'https://a.mp3');
      expect(seg.spokenText, isNull);
      expect(seg.resumeAfter, isTrue);
      expect(seg.tags, contains('geology'));
    });
  });

  group('ExploreRotationScheduler.urgent (location-priority interruption)', () {
    test('fires once for a close candidate, then stays quiet for the same id', () {
      final s = ExploreRotationScheduler();
      final candidate = _c('silver-springs', ExploreCategory.whereHeaded);
      final first = s.urgent(candidate, isCloseEnough: true);
      expect(first, isNotNull);
      expect(first!.id, contains('urgent'));

      final second = s.urgent(candidate, isCloseEnough: true);
      expect(second, isNull, reason: 'already announced this trip');
    });

    test('does not fire when not close enough', () {
      final s = ExploreRotationScheduler();
      final candidate = _c('silver-springs', ExploreCategory.whereHeaded);
      expect(s.urgent(candidate, isCloseEnough: false), isNull);
    });

    test('an urgent cue for a candidate NOT in the pool does not disturb the '
        'normal tier scan', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('headed', ExploreCategory.whereHeaded)],
          ExploreCategory.whereYouAre: [_c('here', ExploreCategory.whereYouAre)],
        });
      s.urgent(_c('urgent-stop', ExploreCategory.whereHeaded), isCloseEnough: true);
      // Tier 1 still wins on the next due() call, unaffected.
      expect(s.due()!.id, contains('headed'));
    });

    test('firing urgent() on a candidate that IS in the pool marks it played, '
        'so due() does not immediately re-pick it', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      s.urgent(_c('a', ExploreCategory.whereHeaded), isCloseEnough: true);
      expect(s.due(), isNull,
          reason: 'a already aired via urgent(); whereHeaded is sticky');
    });
  });

  group('ExploreRotationScheduler.reset', () {
    test('clears play history and urgent memory', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      s.due();
      s.reset();
      expect(s.hasPlayed(ExploreCategory.whereHeaded, 'a'), isFalse);
      expect(s.due(), isNotNull);
    });
  });

  group('RadioEngineService integration', () {
    RadioEngineService buildEngine({
      required ExploreRotationScheduler explore,
      bool exploreMode = true,
    }) =>
        RadioEngineService(
          queue: QueueManagerService(),
          playback: PlaybackController(),
          station: StationManager(),
          stories: StoryScheduler(),
          announcements: AnnouncementScheduler(),
          gps: GPSAudioScheduler(),
          history: HistoryManager(),
          preferences: UserPreferenceManager(),
          // quietGapSongs: 1 so it would fire after a single song — proves
          // Explore mode genuinely supersedes it rather than winning by luck.
          discovery: BackgroundDiscoveryScheduler(quietGapSongs: 1)
            ..updateNearby([_discoveryDecoy]),
          explore: explore,
        )..setExploreMode(exploreMode);

    const station = RadioStation(id: 's1', name: 'Marion County Explore');
    const playlist = [
      Song(id: '1', stationId: 's1', title: 'Song One', audioUrl: 'a1'),
      Song(id: '2', stationId: 's1', title: 'Song Two', audioUrl: 'a2'),
    ];

    test('exploreMode plays the Explore rotation instead of the normal '
        'discovery/location-banter chain', () {
      final explore = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.county: [_c('marion-fact', ExploreCategory.county)],
        });
      final engine = buildEngine(explore: explore);
      engine.djBanter.enabled = false;
      engine.station.load(station: station, playlist: playlist);

      engine.start();
      engine.onSegmentCompleted(); // song ends → Explore checked immediately
      final current = engine.playback.current!.segment;
      expect(current.title, contains('marion-fact'));
      expect(current.tags, contains('explore'));
    });

    test('exploreMode with nothing due falls through to DJ banter/music, '
        'never silent', () {
      final engine = buildEngine(explore: ExploreRotationScheduler());
      engine.station.load(station: station, playlist: playlist);

      engine.start();
      engine.onSegmentCompleted();
      // Either DJ banter filled the gap or music simply continued — either
      // way playback never stops.
      expect(engine.playback.current, isNotNull);
    });

    test('Radio mode (exploreMode off) is completely unaffected — normal '
        'discovery still fires', () {
      final engine = buildEngine(
        explore: ExploreRotationScheduler(),
        exploreMode: false,
      );
      engine.djBanter.enabled = false;
      engine.station.load(station: station, playlist: playlist);

      engine.start();
      engine.onSegmentCompleted();
      final current = engine.playback.current!.segment;
      expect(current.tags, contains('wildlife'));
    });
  });
}

final _discoveryDecoy = DiscoveryCandidate(
  id: 'decoy',
  category: DiscoveryCategory.wildlife,
  title: 'decoy',
  distanceMeters: 10,
  spokenText: 'decoy',
);
