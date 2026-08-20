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
  group('ExploreRotationScheduler — local-color BLOCK building (STAY '
      'LOCAL LONGER)', () {
    test('a rich local pool produces one block containing everything '
        'unplayed, back-to-back, in a single due() call', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [
            _c('history', ExploreCategory.whereYouAre),
            _c('facts', ExploreCategory.whereYouAre),
          ],
          ExploreCategory.history: [
            _c('broader-history', ExploreCategory.history),
          ],
        });
      final block = s.due();
      expect(block.length, 3);
    });

    test('the block respects the size cap even with much more unplayed '
        'content available', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [
            for (var i = 0; i < 20; i++)
              _c('item-$i', ExploreCategory.whereYouAre),
          ],
        });
      final block = s.due();
      expect(block.length, 8); // _kMaxLocalColorBlockSize
    });

    test('an empty pool produces an empty block — never silent, the caller '
        'falls back to music', () {
      final s = ExploreRotationScheduler();
      expect(s.due(), isEmpty);
    });

    test('once a block\'s content is exhausted, the next due() call returns '
        'an empty block rather than repeating', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [
            _c('a', ExploreCategory.whereYouAre),
            _c('b', ExploreCategory.whereYouAre),
          ],
        });
      expect(s.due().length, 2); // both play in one block
      expect(s.due(), isEmpty); // nothing left; no repeats
    });

    test('ahead-of-travel (teaser/reveal) is always checked before ever '
        'building a local-color block', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.teaser: [_c('tease:x', ExploreCategory.teaser)],
          ExploreCategory.whereYouAre: [
            _c('local', ExploreCategory.whereYouAre),
          ],
        });
      final result = s.due();
      expect(result.single.tags, contains('teaser'),
          reason: 'the teaser wins even though local content is also '
              'available');
    });
  });

  group('ExploreRotationScheduler — tier-first local color (STAY LOCAL '
      'LONGER)', () {
    test('CURRENT-TOWN tier beats NEARBY tier regardless of type-priority '
        '— the direct fix for a neighboring town\'s park outranking my own '
        'town\'s history', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [
            // A neighboring town's park: low (favorable) type-priority,
            // but ~15mi away — shaped like _nearbyLocationCandidates' real
            // output.
            _c('neighboring-town-park', ExploreCategory.whereYouAre,
                aheadPriority: 0, distanceMeters: 24140),
            // My own town's own content: no type-priority at all
            // (default), but essentially at distance 0 — shaped like
            // _fromLocationContent's real output.
            _c('my-town-history', ExploreCategory.whereYouAre,
                distanceMeters: 500),
          ],
        });
      final block = s.due();
      expect(block.first.id, contains('my-town-history'),
          reason: 'current-town tier wins even though the neighboring '
              'park has a more favorable type-priority');
    });

    test('the fallback-starvation fix: whereYouAre/events/county/history '
        'are ALL genuinely reachable together in one block, not stuck '
        'repeating whereYouAre forever', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [
            _c('town', ExploreCategory.whereYouAre),
          ],
          ExploreCategory.events: [
            _c('fair', ExploreCategory.events, isAheadOfTravel: false),
          ],
          ExploreCategory.county: [_c('county-fact', ExploreCategory.county)],
          ExploreCategory.history: [_c('broader', ExploreCategory.history)],
        });
      final ids = s.due().map((seg) => seg.id).toList();
      expect(ids.any((i) => i.contains('town')), isTrue);
      expect(ids.any((i) => i.contains('fair')), isTrue);
      expect(ids.any((i) => i.contains('county-fact')), isTrue);
      expect(ids.any((i) => i.contains('broader')), isTrue);
    });

    test('expansion ordering end-to-end: current-town tier before nearby '
        'tier before county-wide, within the block\'s own ordering', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [
            _c('current-town-item', ExploreCategory.whereYouAre,
                distanceMeters: 500),
            _c('nearby-town-item', ExploreCategory.whereYouAre,
                distanceMeters: 24140),
          ],
          ExploreCategory.county: [_c('county-item', ExploreCategory.county)],
        });
      final ids = s.due().map((seg) => seg.id).toList();
      final currentIdx = ids.indexWhere((i) => i.contains('current-town-item'));
      final nearbyIdx = ids.indexWhere((i) => i.contains('nearby-town-item'));
      final countyIdx = ids.indexWhere((i) => i.contains('county-item'));
      expect(currentIdx, lessThan(nearbyIdx));
      expect(nearbyIdx, lessThan(countyIdx));
    });

    test('isAheadOfTravel exclusion: an ahead-cone events candidate is '
        'reserved for the REVEAL path and never surfaces via local color — '
        'while a candidate left at the DEFAULT isAheadOfTravel:true in '
        'every OTHER category is still perfectly pickable', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.events: [
            // isAheadOfTravel defaults true -- an ahead-cone detection.
            _c('ahead-cone-event', ExploreCategory.events,
                distanceMeters: 1000),
          ],
        });
      // It's a REVEAL, not plain local color -- due() builds a session.
      final result = s.due();
      expect(
        result.any((seg) => seg.id.contains('ahead-cone-event')),
        isTrue,
        reason: 'still plays -- via the REVEAL/session path, not local '
            'color',
      );

      // A whereYouAre candidate (also defaulting isAheadOfTravel:true, but
      // NOT in the events category, so the exclusion never applies to it)
      // must remain pickable by local color on its own.
      final s2 = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [
            _c('local-item', ExploreCategory.whereYouAre),
          ],
        });
      expect(s2.select()!.id, 'local-item');
    });

    test('a nearby-fallback (isAheadOfTravel:false) events candidate IS '
        'reachable via local color, never mistaken for an ahead-of-travel '
        'reveal', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.events: [
            _c('town-fair', ExploreCategory.events, distanceMeters: 3000,
                isAheadOfTravel: false),
          ],
        });
      final block = s.due();
      expect(block.single.id, contains('town-fair'));
      expect(block.single.tags, isNot(contains('session_opener')),
          reason: 'a single plain local-color segment, not a session');
    });

    test('wildlife soft guarantee: an unseen wildlife item is forced into '
        'the block within a few picks, even when higher-tier non-wildlife '
        'content would otherwise keep winning', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [
            for (var i = 0; i < 6; i++)
              _c('history-$i', ExploreCategory.whereYouAre,
                  distanceMeters: 500),
          ],
          ExploreCategory.wildlife: [
            // No distance -- county-wide tier, would otherwise lose to
            // every current-town whereYouAre item, every time.
            _c('bobcat', ExploreCategory.wildlife),
          ],
        });
      final block = s.due();
      final wildlifeIdx = block.indexWhere((seg) => seg.id.contains('bobcat'));
      expect(wildlifeIdx, greaterThanOrEqualTo(0),
          reason: 'wildlife must not be starved out of a long block '
              'entirely');
      expect(wildlifeIdx, lessThanOrEqualTo(3),
          reason: 'forced in within _kWildlifeGuaranteeEveryNPicks picks');
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

      // Sticky: exhausted, but must not reset/repeat, and there's nothing
      // else anywhere, so the next block is empty.
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
        final info = s.due();
        phrases.add(info.isEmpty ? null : info.single.spokenText);
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

  group('ExploreRotationScheduler — local color: no repeats, ever', () {
    test('does not repeat within a block — two items in the same category '
        'both play, as distinct pieces, in one block', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.history: [
            _c('black-bear', ExploreCategory.history),
            _c('alligator', ExploreCategory.history),
          ],
        });
      final block = s.due();
      final ids = block.map((seg) => seg.id).toList();
      expect(ids.any((id) => id.contains('black-bear')), isTrue);
      expect(ids.any((id) => id.contains('alligator')), isTrue);
      expect(ids.length, 2, reason: 'each unique item plays exactly once');
    });

    test('CRITICAL: once a category\'s content is exhausted, it is NEVER '
        'repeated — a later due() call returns an empty block rather than '
        'replaying already-heard content', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.history: [_c('only', ExploreCategory.history)],
        });
      final first = s.due();
      expect(first.single.id, contains('only'));
      expect(s.due(), isEmpty,
          reason: 'the only history item already aired; must not repeat it');
    });

    test('a STICKY category (whereHeaded) does NOT reset — once its single '
        'item has aired via a session, it stays quiet rather than '
        're-triggering while still being approached', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      final session = s.due(); // a REVEAL session
      expect(session.any((seg) => seg.id.contains('a')), isTrue);
      expect(s.due(), isEmpty,
          reason: 'whereHeaded is sticky and there is nothing else to say');
    });

    test('emits recorded audio when present, else spoken text, and carries '
        'the tellMeMoreContext through', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.geology: [
            _c('aquifer', ExploreCategory.geology, audioUrl: 'https://a.mp3'),
          ],
        });
      final seg = s.due().single;
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
      // skips it — it's only reachable via local color, a single segment.
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
          'single local-color segment');
    });

    test('a related candidate consumed by a session counts toward its own '
        'category exhaustion — a later due() call prefers a still-unplayed '
        'item in the same category over an immediate repeat', () {
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
      final session = s.due(); // session consumes 'manatee' as related content
      expect(session.any((seg) => seg.id.contains('manatee')), isTrue);

      final next = s.due(); // local color — manatee already gone
      expect(next.single.id, contains('gopher-tortoise'),
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
      // the whereHeaded REVEAL still wins on the next due() call, unaffected.
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
    test('clears play history and urgent memory', () {
      final s = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereHeaded: [_c('a', ExploreCategory.whereHeaded)],
        });
      s.due(); // consumes 'a' via a session
      s.reset();
      expect(s.hasPlayed(ExploreCategory.whereHeaded, 'a'), isFalse);
      // 'a' unseen again -- proves play history was genuinely reset.
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

    test('a local-color block plays every unplayed piece back-to-back '
        'before any song plays', () {
      final explore = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.whereYouAre: [
            _c('history', ExploreCategory.whereYouAre),
            _c('facts', ExploreCategory.whereYouAre),
            _c('events', ExploreCategory.whereYouAre),
          ],
        });
      final engine = buildEngine(explore: explore);
      engine.djBanter.enabled = false;
      engine.station.load(station: station, playlist: playlist);

      engine.start();
      final seenIds = <String>[];
      AudioSegmentType? lastType;
      for (var i = 0; i < 6; i++) {
        final seg = engine.playback.current!.segment;
        seenIds.add(seg.id);
        lastType = seg.type;
        if (lastType == AudioSegmentType.music) break;
        engine.onSegmentCompleted();
      }
      expect(seenIds.any((id) => id.contains('history')), isTrue);
      expect(seenIds.any((id) => id.contains('facts')), isTrue);
      expect(seenIds.any((id) => id.contains('events')), isTrue);
      expect(lastType, AudioSegmentType.music,
          reason: 'the whole block plays before any song, then music '
              'follows as the break');
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

    test('a cold start with a resolvable place opens with the personalized '
        'greeting, before any other discovery content — moving or '
        'stationary makes no difference, only whether a place is known', () {
      final explore = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.county: [_c('marion-fact', ExploreCategory.county)],
        });
      final engine = buildEngine(explore: explore)
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

    test('a cold start with no resolvable place name skips the greeting — '
        'never invents a place — but still opens with discovery content, '
        'not a song', () {
      final explore = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.county: [_c('marion-fact', ExploreCategory.county)],
        });
      final engine = buildEngine(explore: explore);
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
      // currentPlaceName left at its default (null).
      engine.station.load(station: station, playlist: playlist);

      engine.start();
      final current = engine.playback.current!.segment;
      expect(current.type, AudioSegmentType.music);
    });

    test('a cold start with a resolvable place but genuinely no discovery '
        'content anywhere still plays the greeting (not silent, not a song '
        '— the greeting alone is still a meaningful opening)', () {
      final engine = buildEngine(explore: ExploreRotationScheduler())
        ..currentPlaceName = 'Ocklawaha';
      engine.station.load(station: station, playlist: playlist);

      engine.start();
      final current = engine.playback.current!.segment;
      expect(current.tags, contains('greeting'));
    });

    test('the cold-start Explore-first check only ever fires once per '
        'session — once history is non-empty, subsequent song boundaries '
        'behave exactly as they always have', () {
      final explore = ExploreRotationScheduler()
        ..updateCandidates({
          ExploreCategory.county: [
            _c('marion-fact', ExploreCategory.county),
          ],
        });
      final engine = buildEngine(explore: explore);
      engine.djBanter.enabled = false;
      engine.station.load(station: station, playlist: playlist);

      engine.start(); // the local-color block plays first (discovery-first)
      expect(engine.playback.current!.segment.tags, contains('county'));

      // Completing that (non-music) segment falls straight to a real song —
      // NOT back through the cold-start branch a second time, since history
      // is no longer empty. That song completing then drives the normal
      // due() call via _injectScheduledContent exactly as it always has;
      // with the county pool now exhausted (never repeats), it lands on
      // another real song.
      engine.onSegmentCompleted();
      engine.onSegmentCompleted();
      expect(engine.playback.current!.segment.type, AudioSegmentType.music,
          reason: 'the normal cadence is unaffected once the one-time '
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
