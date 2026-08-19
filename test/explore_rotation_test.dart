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
  int aheadPriority = 1000,
}) =>
    ExploreCandidate(
      id: id,
      category: cat,
      title: '$id (${cat.label})',
      audioUrl: audioUrl,
      spokenText: spokenText,
      aheadPriority: aheadPriority,
    );

void main() {
  group('ExploreRotationScheduler — 3-step cycle (INFORMATION → WILDLIFE → '
      'SONG GAP → repeat)', () {
    test('a full cycle: INFORMATION, then WILDLIFE, then a song gap, then '
        'INFORMATION again (pool exhausted → resets, non-sticky)', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.county: [_c('marion-fact', ExploreCategory.county)],
          ExploreCategory.wildlife: [_c('bobcat', ExploreCategory.wildlife)],
        });
      expect(s.due()!.tags, contains('county')); // position 0: INFORMATION
      expect(s.due()!.tags, contains('wildlife')); // position 1: WILDLIFE
      expect(s.due(), isNull); // position 2: SONG GAP — let one song play
      // Lap 2 — the county pool (one item) was exhausted, so it resets and
      // repeats rather than the cycle silently skipping INFORMATION.
      expect(s.due()!.tags, contains('county'));
    });

    test('WILDLIFE is a guaranteed slot every cycle, even when INFORMATION '
        'also found something — not conditional on "nothing ahead" like the '
        'old tier-priority model', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
          ExploreCategory.wildlife: [_c('w', ExploreCategory.wildlife)],
        });
      expect(s.due()!.tags, contains('whereHeaded'));
      expect(s.due()!.tags, contains('wildlife'),
          reason: 'wildlife plays even though something was ahead this lap');
    });

    test('an empty INFORMATION or WILDLIFE slot silently becomes an extra '
        'song rather than borrowing from a later position', () {
      final s = ExploreRotationScheduler(); // nothing in any category
      expect(s.due(), isNull); // INFORMATION: nothing → null
      expect(s.due(), isNull); // WILDLIFE: nothing → null
      expect(s.due(), isNull); // SONG GAP: always null
    });
  });

  group('ExploreRotationScheduler — INFORMATION slot sourcing', () {
    test('within INFORMATION, WHERE YOU ARE beats the broader COUNTY '
        'fallback, which beats HISTORY', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [_c('y', ExploreCategory.whereYouAre)],
          ExploreCategory.county: [_c('c', ExploreCategory.county)],
          ExploreCategory.history: [_c('h', ExploreCategory.history)],
        });
      expect(s.select()!.id, 'y');
    });

    test('a candidate with neither audio nor spoken text never fills a slot',
        () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.county: [
            _c('empty', ExploreCategory.county, spokenText: null),
          ],
          ExploreCategory.history: [_c('h', ExploreCategory.history)],
        });
      expect(s.select()!.id, 'h');
    });

    test('type-priority ranks a higher-priority ahead candidate over a '
        'lower-priority one, regardless of list order', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [
            _c('town-x', ExploreCategory.whereHeaded, aheadPriority: 5),
            _c('state-park-y', ExploreCategory.whereHeaded, aheadPriority: 0),
          ],
        });
      expect(s.select()!.id, 'state-park-y');
    });

    test('an event can outrank a lower-priority location even though '
        "they're different categories", () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [
            _c('town', ExploreCategory.whereHeaded, aheadPriority: 5),
          ],
          ExploreCategory.events: [
            _c('festival', ExploreCategory.events, aheadPriority: 4),
          ],
        });
      expect(s.select()!.id, 'festival');
    });
  });

  group('ExploreRotationScheduler — two-stage teaser', () {
    test('a teaser plays varied generic phrasing, not the candidate\'s own '
        'spokenText, and fires once (sticky, never resets)', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.teaser: [
            _c('tease:silver-springs', ExploreCategory.teaser,
                spokenText: 'REAL STORY TEXT (should never be spoken here)'),
          ],
        });
      final seg = s.due()!;
      expect(seg.spokenText, isNot('REAL STORY TEXT (should never be spoken here)'));
      expect(seg.tags, contains('teaser'));

      s.due(); // WILDLIFE (empty)
      s.due(); // SONG GAP
      // Lap 2 — the teaser is sticky: exhausted, but must not reset/repeat.
      expect(s.due(), isNull);
    });

    test('teasing a destination is independent of its later full reveal — '
        'different pools, the reveal is unaffected by whether it was '
        'teased first', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.teaser: [
            _c('tease:x', ExploreCategory.teaser),
          ],
        });
      s.due(); // teaser plays and is consumed
      s.due(); // WILDLIFE
      s.due(); // SONG GAP

      // The real destination becomes eligible for full reveal on a later
      // lap (in production: once close enough, the provider stops emitting
      // the teaser and starts emitting the full `ahead:` candidate instead).
      s.updateCandidates({
        ExploreCategory.whereHeaded: [_c('ahead:x', ExploreCategory.whereHeaded)],
      });
      final seg = s.due()!;
      expect(seg.tags, contains('whereHeaded'));
      expect(seg.spokenText, 'A short fact.'); // the real story, not a teaser phrase
    });

    test('teaser phrasing varies across successive teases — three different '
        'teaser ids get three different phrases, no repeat while unused '
        'phrases exist', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.teaser: [
            _c('t1', ExploreCategory.teaser),
            _c('t2', ExploreCategory.teaser),
            _c('t3', ExploreCategory.teaser),
          ],
        });
      final phrases = <String?>[];
      for (var lap = 0; lap < 3; lap++) {
        phrases.add(s.due()?.spokenText); // INFORMATION
        s.due(); // WILDLIFE (empty)
        s.due(); // SONG GAP
      }
      expect(phrases.toSet().length, 3,
          reason: 'three distinct teasers should not repeat the same phrase');
    });
  });

  group('ExploreRotationScheduler — no-repeat / exhaustion reset', () {
    test('does not repeat a played item; prefers another unused item in the '
        'same category', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.history: [
            _c('black-bear', ExploreCategory.history),
            _c('alligator', ExploreCategory.history),
          ],
        });
      final first = s.due(); // INFORMATION (history is the fallback here)
      expect(first!.id, contains('black-bear'));
      expect(s.hasPlayed(ExploreCategory.history, 'black-bear'), isTrue);
      s.due(); // WILDLIFE
      s.due(); // SONG GAP

      final second = s.due(); // INFORMATION, lap 2
      expect(second!.id, contains('alligator'),
          reason: 'black-bear already aired; the other item plays');
    });

    test('a non-sticky category with only one candidate repeats it once the '
        'pool is exhausted, rather than going quiet (literal "don\'t repeat '
        'while other unused content exists" — there is no other content)',
        () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.history: [_c('only', ExploreCategory.history)],
        });
      expect(s.due()!.id, contains('only'));
      s.due();
      s.due();
      expect(s.due()!.id, contains('only'),
          reason: 'the whole (one-item) pool was exhausted, so it resets');
    });

    test('a full non-sticky category (3 items) plays each exactly once, '
        'then resets and repeats the first — CONTENT POOL RESET only once '
        'genuinely exhausted, never prematurely', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.history: [
            _c('h1', ExploreCategory.history),
            _c('h2', ExploreCategory.history),
            _c('h3', ExploreCategory.history),
          ],
        });
      final ids = <String>[];
      for (var lap = 0; lap < 3; lap++) {
        ids.add(s.due()!.id);
        s.due();
        s.due();
      }
      expect(
        ids.map((i) => i.contains('h1')
            ? 'h1'
            : i.contains('h2')
                ? 'h2'
                : 'h3'),
        containsAll(['h1', 'h2', 'h3']),
      );
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
      expect(s.due()!.id, contains('a')); // INFORMATION, lap 1
      s.due(); // WILDLIFE
      s.due(); // SONG GAP
      expect(s.due(), isNull,
          reason: 'whereHeaded is sticky — exhausted, but must not reset');
    });

    test('WILDLIFE prefers actual wildlife content over nature/geology, '
        'falling back only when wildlife is empty', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.nature: [_c('plant', ExploreCategory.nature)],
          ExploreCategory.wildlife: [_c('bobcat', ExploreCategory.wildlife)],
        });
      s.due(); // INFORMATION (empty)
      expect(s.due()!.id, contains('bobcat')); // WILDLIFE prefers wildlife over nature
    });

    test('emits recorded audio when present, else spoken text, and carries '
        'the tellMeMoreContext through', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.geology: [
            _c('aquifer', ExploreCategory.geology, audioUrl: 'https://a.mp3'),
          ],
        });
      s.due(); // INFORMATION (empty)
      final seg = s.due()!; // WILDLIFE → falls to geology
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
        'normal cycle', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('headed', ExploreCategory.whereHeaded)],
        });
      s.urgent(_c('urgent-stop', ExploreCategory.whereHeaded), isCloseEnough: true);
      // INFORMATION still wins on the next due() call, unaffected.
      expect(s.due()!.id, contains('headed'));
    });

    test('firing urgent() on a candidate that IS in the pool marks it '
        'played, so due() does not immediately re-pick it', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      s.urgent(_c('a', ExploreCategory.whereHeaded), isCloseEnough: true);
      expect(s.due(), isNull,
          reason: 'a already aired via urgent(); whereHeaded is sticky');
    });
  });

  group('ExploreRotationScheduler — persistence hooks', () {
    test('snapshotPlayed/restorePlayed round-trips played history', () {
      final s1 = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.history: [_c('h1', ExploreCategory.history)],
        });
      s1.due(); // plays h1
      final snapshot = s1.snapshotPlayed();
      expect(snapshot[ExploreCategory.history], contains('h1'));

      final s2 = ExploreRotationScheduler()..restorePlayed(snapshot);
      expect(s2.hasPlayed(ExploreCategory.history, 'h1'), isTrue);
    });

    test('restorePlayed merges rather than overwrites existing state', () {
      final s = ExploreRotationScheduler()
        ..restorePlayed({
          ExploreCategory.history: {'old'},
        })
        ..restorePlayed({
          ExploreCategory.history: {'new'},
        });
      expect(s.hasPlayed(ExploreCategory.history, 'old'), isTrue);
      expect(s.hasPlayed(ExploreCategory.history, 'new'), isTrue);
    });
  });

  group('ExploreRotationScheduler.reset', () {
    test('clears play history, urgent memory, and cycle position', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      s.due(); // consumes 'a', advances past INFORMATION
      s.reset();
      expect(s.hasPlayed(ExploreCategory.whereHeaded, 'a'), isFalse);
      // Back at INFORMATION (position 0) with 'a' unseen again — proves both
      // play history AND cycle position were reset, not just one.
      expect(s.due()!.id, contains('a'));
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
