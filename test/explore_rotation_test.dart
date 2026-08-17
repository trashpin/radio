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
  group('ExploreRotationScheduler.select (fixed order, skip-if-empty)', () {
    test('rotates WHERE HEADED > WHERE YOU ARE > COUNTY > WILDLIFE > NATURE '
        '> GEOLOGY > HISTORY, in that order', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
          ExploreCategory.history: [_c('b', ExploreCategory.history)],
        });
      // whereHeaded comes first even though history is also available.
      expect(s.select()!.id, 'a');
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

  group('ExploreRotationScheduler.due (continues rotation, anti-repeat)', () {
    test('after playing WHERE HEADED, the next due() continues from WHERE '
        'YOU ARE rather than restarting the rotation', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('headed', ExploreCategory.whereHeaded)],
          ExploreCategory.whereYouAre: [_c('here', ExploreCategory.whereYouAre)],
        });
      expect(s.due()!.id.contains('headed'), isTrue);
      expect(s.due()!.id.contains('here'), isTrue);
    });

    test('does not repeat a recently played item; prefers another in the '
        'same category', () {
      final s = ExploreRotationScheduler(cooldownPlays: 5)
        ..updateCandidates({
          ExploreCategory.wildlife: [
            _c('black-bear', ExploreCategory.wildlife),
            _c('alligator', ExploreCategory.wildlife),
          ],
        });
      final first = s.due();
      expect(first!.id, contains('black-bear'));
      expect(s.recentlyPlayed('black-bear'), isTrue);

      final second = s.due();
      expect(second!.id, contains('alligator'),
          reason: 'black-bear is on cooldown; the other wildlife item plays');
    });

    test('a full lap with only one candidate returns null once it is on '
        'cooldown, rather than repeating immediately', () {
      final s = ExploreRotationScheduler(cooldownPlays: 5)
        ..updateCandidates({
          ExploreCategory.history: [_c('only', ExploreCategory.history)],
        });
      expect(s.due()!.id, contains('only'));
      expect(s.due(), isNull);
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

    test('does not disturb the normal rotation cursor', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('headed', ExploreCategory.whereHeaded)],
          ExploreCategory.whereYouAre: [_c('here', ExploreCategory.whereYouAre)],
        });
      s.urgent(_c('urgent-stop', ExploreCategory.whereHeaded), isCloseEnough: true);
      // The normal rotation still starts at WHERE HEADED, unaffected.
      expect(s.due()!.id, contains('headed'));
    });
  });

  group('ExploreRotationScheduler.reset', () {
    test('clears rotation position, play history, and urgent memory', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      s.due();
      s.reset();
      expect(s.recentlyPlayed('a'), isFalse);
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
