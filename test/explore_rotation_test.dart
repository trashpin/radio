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
  double? distanceMeters,
  String? sessionKey,
  bool isAheadOfTravel = true,
}) =>
    ExploreCandidate(
      id: id,
      category: cat,
      title: '$id (${cat.label})',
      audioUrl: audioUrl,
      spokenText: spokenText,
      aheadPriority: aheadPriority,
      distanceMeters: distanceMeters,
      sessionKey: sessionKey,
      isAheadOfTravel: isAheadOfTravel,
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
      expect(s.due().single.tags, contains('county')); // position 0: INFORMATION
      expect(s.due().single.tags, contains('wildlife')); // position 1: WILDLIFE
      expect(s.due(), isEmpty); // position 2: SONG GAP — let one song play
      // Lap 2 — the county pool (one item) was exhausted, so it resets and
      // repeats rather than the cycle silently skipping INFORMATION.
      expect(s.due().single.tags, contains('county'));
    });

    test('WILDLIFE is a guaranteed slot every cycle, even when INFORMATION '
        'also found something — not conditional on "nothing ahead" like the '
        'old tier-priority model', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
          ExploreCategory.wildlife: [_c('w', ExploreCategory.wildlife)],
        });
      // whereHeaded is a REVEAL, so INFORMATION expands into a session (at
      // least: session-opener, then the story itself somewhere in the batch).
      final info = s.due();
      expect(info.length, greaterThanOrEqualTo(2));
      expect(info.any((seg) => seg.tags.contains('whereHeaded')), isTrue);
      expect(s.due().single.tags, contains('wildlife'),
          reason: 'wildlife plays even though something was ahead this lap');
    });

    test('an empty INFORMATION or WILDLIFE slot silently becomes an extra '
        'song rather than borrowing from a later position', () {
      final s = ExploreRotationScheduler(); // nothing in any category
      expect(s.due(), isEmpty); // INFORMATION: nothing → empty
      expect(s.due(), isEmpty); // WILDLIFE: nothing → empty
      expect(s.due(), isEmpty); // SONG GAP: always empty
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

    test('LOCAL FIRST: within WHERE YOU ARE, a closer same-priority '
        'candidate is tried before a farther one — current town/area before '
        'a farther nearby town, with no separate distance-band category', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [
            _c('far-town-park', ExploreCategory.whereYouAre,
                aheadPriority: 0, distanceMeters: 30000),
            _c('current-area-park', ExploreCategory.whereYouAre,
                aheadPriority: 0, distanceMeters: 2000),
          ],
        });
      expect(s.select()!.id, 'current-area-park');
    });

    test('EVENTS is an explicit INFORMATION fallback tier, after WHERE YOU '
        'ARE and before COUNTY — current/nearby-town events considered '
        'ahead of county-wide content', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.events: [
            _c('town-fair', ExploreCategory.events, distanceMeters: 3000,
                isAheadOfTravel: false), // merely nearby, not ahead-of-travel
          ],
          ExploreCategory.county: [_c('county-fact', ExploreCategory.county)],
        });
      expect(s.select()!.id, 'town-fair');
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
      final seg = s.due().single;
      expect(seg.spokenText, isNot('REAL STORY TEXT (should never be spoken here)'));
      expect(seg.tags, contains('teaser'));

      s.due(); // WILDLIFE (empty)
      s.due(); // SONG GAP
      // Lap 2 — the teaser is sticky: exhausted, but must not reset/repeat.
      expect(s.due(), isEmpty);
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
      // whereHeaded is a REVEAL → a session (session-opener, then the story).
      final session = s.due();
      expect(session.length, greaterThanOrEqualTo(2));
      final story = session.firstWhere((seg) => seg.tags.contains('whereHeaded'));
      expect(story.spokenText, 'A short fact.'); // the real story, not a teaser phrase
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
        final info = s.due(); // INFORMATION
        phrases.add(info.isEmpty ? null : info.single.spokenText);
        s.due(); // WILDLIFE (empty)
        s.due(); // SONG GAP
      }
      expect(phrases.toSet().length, 3,
          reason: 'three distinct teasers should not repeat the same phrase');
    });

    test('the session-opener (spoken at the start of every REVEAL session) '
        'uses its own phrase pool and cursor, entirely independent of the '
        'standalone far-away teaser', () {
      final standalone = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.teaser: [_c('tease:x', ExploreCategory.teaser)],
        });
      final standaloneSeg = standalone.due().single;

      final session = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      final sessionOpener = session.due().first;

      expect(sessionOpener.tags, contains('session_opener'));
      expect(sessionOpener.spokenText, isNot(standaloneSeg.spokenText));
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
      final first = s.due().single; // INFORMATION (history is the fallback here)
      expect(first.id, contains('black-bear'));
      expect(s.hasPlayed(ExploreCategory.history, 'black-bear'), isTrue);
      s.due(); // WILDLIFE
      s.due(); // SONG GAP

      final second = s.due().single; // INFORMATION, lap 2
      expect(second.id, contains('alligator'),
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
      expect(s.due().single.id, contains('only'));
      s.due();
      s.due();
      expect(s.due().single.id, contains('only'),
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
        ids.add(s.due().single.id);
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
      expect(s.due().single.id, contains('h1'),
          reason: 'pool exhausted after 3 plays; resets and repeats the first');
    });

    test('a STICKY category (whereHeaded) does NOT reset — once its single '
        'item has aired, it stays quiet rather than re-triggering while '
        'still being approached', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      final session = s.due(); // INFORMATION, lap 1 — a REVEAL session
      expect(session.any((seg) => seg.id.contains('a')), isTrue);
      s.due(); // WILDLIFE
      s.due(); // SONG GAP
      expect(s.due(), isEmpty,
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
      expect(s.due().single.id, contains('bobcat')); // WILDLIFE prefers wildlife over nature
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
      final seg = s.due().single; // WILDLIFE → falls to geology
      expect(seg.audioUrl, 'https://a.mp3');
      expect(seg.spokenText, isNull);
      expect(seg.resumeAfter, isTrue);
      expect(seg.tags, contains('geology'));
    });
  });

  group('ExploreRotationScheduler — travel-companion SESSIONS', () {
    test('a REVEAL with no related content produces exactly 3 segments: '
        'session-opener, intro, story', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [
            _c('silver-springs', ExploreCategory.whereHeaded,
                distanceMeters: 4828, sessionKey: 'loc:silver-springs'),
          ],
        });
      final session = s.due();
      expect(session.length, 3);
      expect(session[0].tags, contains('session_opener'));
      expect(session[1].spokenText, contains('miles from'));
      expect(session[2].tags, contains('whereHeaded'));
      expect(session[2].spokenText, 'A short fact.');
    });

    test('a REVEAL with genuinely related content (matching sessionKey) '
        'produces all 5 segments: opener, intro, story, transition, related',
        () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [
            _c('silver-springs', ExploreCategory.whereHeaded,
                distanceMeters: 4828, sessionKey: 'loc:silver-springs'),
          ],
          ExploreCategory.wildlife: [
            _c('manatee', ExploreCategory.wildlife,
                sessionKey: 'loc:silver-springs'),
          ],
        });
      final session = s.due();
      expect(session.length, 5);
      expect(session[3].tags, contains('wildlife')); // transition beat
      expect(session[4].id, contains('manatee')); // related content itself
      expect(session[4].tags, contains('wildlife'));
    });

    test('a related candidate with a NON-matching sessionKey is correctly '
        'ignored — no forced/random connection', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [
            _c('silver-springs', ExploreCategory.whereHeaded,
                distanceMeters: 4828, sessionKey: 'loc:silver-springs'),
          ],
          ExploreCategory.wildlife: [
            _c('unrelated-bird', ExploreCategory.wildlife,
                sessionKey: 'loc:somewhere-else'),
          ],
        });
      expect(s.due().length, 3, reason: 'no genuinely-linked content exists');
    });

    test('a related candidate with a NULL sessionKey (ungeo-scoped species '
        'pool) is correctly ignored', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [
            _c('silver-springs', ExploreCategory.whereHeaded,
                distanceMeters: 4828, sessionKey: 'loc:silver-springs'),
          ],
          ExploreCategory.wildlife: [
            _c('generic-species', ExploreCategory.wildlife), // sessionKey: null
          ],
        });
      expect(s.due().length, 3);
    });

    test('an events-category REVEAL (sessionKey "evt:...") never finds '
        'related content — only location-derived candidates ever carry a '
        '"loc:" sessionKey — and degrades gracefully to 3 segments', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.events: [
            _c('harvest-fest', ExploreCategory.events,
                distanceMeters: 1609, sessionKey: 'evt:harvest-fest'),
          ],
          ExploreCategory.history: [
            _c('unrelated-history', ExploreCategory.history,
                sessionKey: 'loc:somewhere-else'),
          ],
        });
      // events (as an ahead-cone reveal, via _pickAheadAcross) is a REVEAL.
      final session = s.due();
      expect(session.length, 3);
    });

    test('a fallback (merely-nearby, not ahead-of-travel) EVENTS pick does '
        'NOT trigger a session, even though it shares a category with the '
        'ahead-cone reveal case', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.events: [
            _c('town-fair', ExploreCategory.events, distanceMeters: 3000,
                isAheadOfTravel: false),
          ],
        });
      // isAheadOfTravel:false means _pickAheadAcross([whereHeaded, events])
      // skips it — it's only reachable via the plain fallback loop in
      // _selectInformationDetailed, so isReveal is false, single segment.
      expect(s.due().length, 1);
    });

    test('an events-category candidate defaults to isAheadOfTravel:true — '
        'production _aheadCandidates output is genuinely a REVEAL by '
        'default; only _nearbyEventCandidates explicitly opts out', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.events: [
            _c('festival', ExploreCategory.events, distanceMeters: 1609,
                sessionKey: 'evt:festival'),
          ],
        });
      expect(s.due().length, 3, reason: 'defaults true → a session, not a '
          'single fallback segment');
    });

    test('a related candidate consumed by a session counts toward its own '
        'category exhaustion — a later WILDLIFE cycle slot prefers a still-'
        'unplayed item in the same category over an immediate repeat', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [
            _c('silver-springs', ExploreCategory.whereHeaded,
                sessionKey: 'loc:silver-springs'),
          ],
          ExploreCategory.wildlife: [
            _c('manatee', ExploreCategory.wildlife,
                sessionKey: 'loc:silver-springs'),
            _c('gopher-tortoise', ExploreCategory.wildlife),
          ],
        });
      final session = s.due(); // INFORMATION — session consumes 'manatee'
      expect(session.any((seg) => seg.id.contains('manatee')), isTrue);

      final wildlifeSlot = s.due(); // WILDLIFE
      expect(wildlifeSlot.single.id, contains('gopher-tortoise'),
          reason: 'manatee already aired via the session; the still-unplayed '
              'gopher-tortoise plays instead of an immediate repeat');
    });

    test('opener/intro segments carry the REVEAL candidate\'s image/'
        'location/tellMeMoreContext; the transition segment carries the '
        'RELATED candidate\'s', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [
            ExploreCandidate(
              id: 'silver-springs',
              category: ExploreCategory.whereHeaded,
              title: 'Silver Springs',
              spokenText: 'The story.',
              imageUrl: 'https://reveal.jpg',
              latitude: 29.2,
              longitude: -82.0,
              distanceMeters: 4828,
              sessionKey: 'loc:silver-springs',
            ),
          ],
          ExploreCategory.wildlife: [
            ExploreCandidate(
              id: 'manatee',
              category: ExploreCategory.wildlife,
              title: 'Manatee',
              spokenText: 'About manatees.',
              imageUrl: 'https://related.jpg',
              latitude: 29.21,
              longitude: -82.01,
              sessionKey: 'loc:silver-springs',
            ),
          ],
        });
      final session = s.due();
      expect(session[0].imageUrl, 'https://reveal.jpg'); // opener
      expect(session[1].imageUrl, 'https://reveal.jpg'); // intro
      expect(session[3].imageUrl, 'https://related.jpg'); // transition
      expect(session[4].imageUrl, 'https://related.jpg'); // related itself
    });

    test('reset() clears the session-opener and related-transition cursors '
        'alongside the teaser cursor', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      final before = s.due().first.spokenText;
      s.reset();
      s.updateCandidates({
        ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
      });
      final after = s.due().first.spokenText;
      expect(after, before,
          reason: 'the session-opener cursor restarted from the beginning');
    });
  });

  group('ExploreRotationScheduler.greetingSegment', () {
    test('interpolates the given place name and varies wording across calls '
        '(round-robin, no repeat while other phrasing is unused)', () {
      final s = ExploreRotationScheduler();
      final texts = [
        s.greetingSegment('Ocklawaha').spokenText,
        s.greetingSegment('Ocklawaha').spokenText,
        s.greetingSegment('Ocklawaha').spokenText,
      ];
      for (final t in texts) {
        expect(t, contains('Ocklawaha'));
      }
      expect(texts.toSet().length, 3,
          reason: 'three calls should not repeat the same template');
    });

    test('carries a time-of-day greeting ("Good morning/afternoon/evening")',
        () {
      final s = ExploreRotationScheduler();
      final text = s.greetingSegment('Ocala').spokenText!;
      expect(
        text.contains('Good morning') ||
            text.contains('Good afternoon') ||
            text.contains('Good evening'),
        isTrue,
      );
    });

    test('is not tied to the no-repeat played-content pool — never counted '
        'in hasPlayed', () {
      final s = ExploreRotationScheduler();
      final seg = s.greetingSegment('Belleview');
      expect(seg.tags, contains('greeting'));
      expect(seg.resumeAfter, isTrue);
      // No category tracks a "greeting" id — confirms this is a synthesized
      // beat, not a pool/exhaustion-tracked candidate like other content.
      for (final cat in ExploreCategory.values) {
        expect(s.hasPlayed(cat, seg.id), isFalse);
      }
    });

    test('reset() restarts the wording cursor from the beginning', () {
      final s = ExploreRotationScheduler();
      final before = s.greetingSegment('Dunnellon').spokenText;
      s.reset();
      final after = s.greetingSegment('Dunnellon').spokenText;
      expect(after, before);
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
      // INFORMATION still wins on the next due() call, unaffected — a
      // whereHeaded REVEAL, so a session (containing 'headed' somewhere).
      final session = s.due();
      expect(session.any((seg) => seg.id.contains('headed')), isTrue);
    });

    test('firing urgent() on a candidate that IS in the pool marks it '
        'played, so due() does not immediately re-pick it', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      s.urgent(_c('a', ExploreCategory.whereHeaded), isCloseEnough: true);
      expect(s.due(), isEmpty,
          reason: 'a already aired via urgent(); whereHeaded is sticky');
    });

    test('urgent() refuses to re-fire for a candidate already narrated via a '
        'due()-built session — the exact "the story plays again" bug this '
        'feature must not have', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('ma-barker', ExploreCategory.whereHeaded)],
        });
      s.due(); // session plays and marks 'ma-barker' played
      final again = s.urgent(_c('ma-barker', ExploreCategory.whereHeaded),
          isCloseEnough: true);
      expect(again, isNull,
          reason: 'already told via the session; urgent must not repeat it');
    });

    test('the inverse ordering: urgent() fires first (simulating the '
        'documented race where a GPS tick beats the next song boundary), '
        'then due() must not ALSO session-build the same candidate', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      s.urgent(_c('a', ExploreCategory.whereHeaded), isCloseEnough: true);
      expect(s.due(), isEmpty,
          reason: 'whereHeaded is sticky and already played via urgent()');
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
      s.due(); // consumes 'a' via a session, advances past INFORMATION
      s.reset();
      expect(s.hasPlayed(ExploreCategory.whereHeaded, 'a'), isFalse);
      // Back at INFORMATION (position 0) with 'a' unseen again — proves both
      // play history AND cycle position were reset, not just one.
      final session = s.due();
      expect(session.any((seg) => seg.id.contains('a')), isTrue);
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

      // Discovery-first: start() alone must already surface Explore content
      // — no song, and no extra onSegmentCompleted() needed to reveal it.
      engine.start();
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

    test('a multi-segment session queues and plays back-to-back before any '
        'song plays', () {
      final explore = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [
            _c('silver-springs', ExploreCategory.whereHeaded,
                distanceMeters: 4828, sessionKey: 'loc:silver-springs'),
          ],
          ExploreCategory.wildlife: [
            _c('manatee', ExploreCategory.wildlife,
                sessionKey: 'loc:silver-springs'),
          ],
        });
      final engine = buildEngine(explore: explore);
      engine.djBanter.enabled = false;
      engine.station.load(station: station, playlist: playlist);

      // Discovery-first: start() alone queues and immediately begins the
      // session — no song, no extra onSegmentCompleted() needed first.
      engine.start();

      // First beat: the session-opener.
      expect(engine.playback.current!.segment.tags, contains('session_opener'));

      // Each subsequent completion should pull the NEXT queued session
      // segment (never re-triggering _injectScheduledContent, since only a
      // completed MUSIC segment does that) until the whole session drains
      // and _takeNext() finally falls back to a song.
      final seenTags = <String>[];
      AudioSegmentType? lastType;
      for (var i = 0; i < 6; i++) {
        final seg = engine.playback.current!.segment;
        seenTags.addAll(seg.tags);
        lastType = seg.type;
        if (lastType == AudioSegmentType.music) break;
        engine.onSegmentCompleted();
      }
      expect(seenTags, contains('whereHeaded')); // the story beat
      expect(seenTags, contains('wildlife')); // the related beat
      expect(lastType, AudioSegmentType.music,
          reason: 'the session fully drains before any song plays');
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

    test('a STATIONARY cold start with a resolvable place opens with the '
        'personalized greeting, before any other discovery content', () {
      final explore = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.county: [_c('marion-fact', ExploreCategory.county)],
        });
      final engine = buildEngine(explore: explore)
        ..isStationary = true
        ..currentPlaceName = 'Ocklawaha';
      engine.djBanter.enabled = false;
      engine.station.load(station: station, playlist: playlist);

      engine.start();
      final first = engine.playback.current!.segment;
      expect(first.tags, contains('greeting'));
      expect(first.spokenText, contains('Ocklawaha'));

      // The greeting is followed by discovery content, not a song.
      engine.onSegmentCompleted();
      final second = engine.playback.current!.segment;
      expect(second.title, contains('marion-fact'));
    });

    test('a MOVING cold start does not play a greeting, but still does not '
        'start with a song when relevant content exists', () {
      final explore = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.county: [_c('marion-fact', ExploreCategory.county)],
        });
      final engine = buildEngine(explore: explore)
        ..isStationary = false
        ..currentPlaceName = 'Ocklawaha';
      engine.djBanter.enabled = false;
      engine.station.load(station: station, playlist: playlist);

      engine.start();
      final current = engine.playback.current!.segment;
      expect(current.tags, isNot(contains('greeting')));
      expect(current.title, contains('marion-fact'));
    });

    test('a cold start with no resolvable place name skips the greeting '
        'even while stationary — never invents a place', () {
      final explore = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.county: [_c('marion-fact', ExploreCategory.county)],
        });
      final engine = buildEngine(explore: explore)..isStationary = true;
      // currentPlaceName left null.
      engine.djBanter.enabled = false;
      engine.station.load(station: station, playlist: playlist);

      engine.start();
      final current = engine.playback.current!.segment;
      expect(current.tags, isNot(contains('greeting')));
      expect(current.title, contains('marion-fact'));
    });

    test('a cold start with truly nothing due anywhere — and no resolvable '
        'place, so not even a greeting — still falls through to music, '
        'never silent', () {
      final engine = buildEngine(explore: ExploreRotationScheduler());
      // isStationary/currentPlaceName left at their defaults (false/null).
      engine.station.load(station: station, playlist: playlist);

      engine.start();
      final current = engine.playback.current!.segment;
      expect(current.type, AudioSegmentType.music);
    });

    test('a STATIONARY cold start with a place but genuinely no discovery '
        'content anywhere still plays the greeting (not silent, not a song '
        '— the greeting alone is still a meaningful opening)', () {
      final engine = buildEngine(explore: ExploreRotationScheduler())
        ..isStationary = true
        ..currentPlaceName = 'Ocklawaha';
      engine.station.load(station: station, playlist: playlist);

      engine.start();
      final current = engine.playback.current!.segment;
      expect(current.tags, contains('greeting'));
    });

    test('the cold-start Explore-first check only ever fires once per '
        'session — once history is non-empty, the normal SONG GAP cadence '
        'is completely untouched', () {
      final explore = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.county: [
            _c('marion-fact', ExploreCategory.county),
          ],
        });
      final engine = buildEngine(explore: explore);
      engine.djBanter.enabled = false;
      engine.station.load(station: station, playlist: playlist);

      engine.start(); // INFORMATION plays first (discovery-first)
      expect(engine.playback.current!.segment.tags, contains('county'));

      // Completing that (non-music) segment falls straight to a real song —
      // NOT back through the cold-start branch a second time, since history
      // is no longer empty. That song completing then drives the normal
      // WILDLIFE slot (empty this lap) via _injectScheduledContent exactly
      // as it always has, landing on another real song.
      engine.onSegmentCompleted();
      engine.onSegmentCompleted();
      expect(engine.playback.current!.segment.type, AudioSegmentType.music,
          reason: 'the normal cycle is unaffected once the one-time '
              'cold-start branch has already fired');
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
