import 'dart:math';

import 'package:explorer_os_mobile/features/dj/banter_studio/banter_category.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/banter_templates.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/dj_banter_clip.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/gps_banter_director.dart';
import 'package:flutter_test/flutter_test.dart';

DjBanterClip _clip(
  String id,
  BanterCategory cat, {
  String text = 'Near {park}.',
  BanterStatus status = BanterStatus.published,
  String? dest,
  String? region,
  String? guide,
}) =>
    DjBanterClip(
      id: id,
      category: cat,
      text: text,
      status: status,
      destinationCode: dest,
      gpsRegion: region,
      guideMode: guide,
    );

void main() {
  group('BanterCategory', () {
    test('has all 19 categories with stable ids and round-trips fromId', () {
      expect(BanterCategory.values.length, 19);
      expect(BanterCategory.historyTease.id, 'history_tease');
      expect(BanterCategory.fromId('history_tease'), BanterCategory.historyTease);
      expect(BanterCategory.fromId('interesting_fact'),
          BanterCategory.interestingFact);
      expect(BanterCategory.fromId('welcome'), BanterCategory.welcome);
      expect(BanterCategory.fromId('nonsense'), isNull);
    });

    test('teases transition into the matching narration', () {
      expect(BanterCategory.historyTease.transition,
          BanterTransition.historyNarration);
      expect(BanterCategory.wildlifeTease.transition,
          BanterTransition.wildlifeNarration);
      expect(BanterCategory.songIntro.transition, BanterTransition.song);
      expect(BanterCategory.stationId.transition, BanterTransition.stationId);
    });
  });

  group('fillBanter', () {
    test('fills GPS placeholders from context', () {
      const ctx = GpsBanterContext(
        park: 'Ocala National Forest',
        county: 'Marion County',
        upcomingAttraction: 'Juniper Springs',
        nearbyWildlife: ['Florida black bears'],
      );
      final line = fillBanter(
        "You're getting close to {upcoming_attraction}. Great habitat for "
        '{nearby_wildlife} here in {park}.',
        ctx,
      );
      expect(line, contains('Juniper Springs'));
      expect(line, contains('Florida black bears'));
      expect(line, contains('Ocala National Forest'));
    });

    test('uses natural fallbacks for missing context', () {
      const ctx = GpsBanterContext();
      final line = fillBanter('Rolling through {park} near {nearby_river}.', ctx);
      expect(line, contains('this area'));
      expect(line, contains('a nearby river'));
    });
  });

  group('buildBanterDrafts', () {
    test('generates the requested count of unique lines', () {
      final drafts = buildBanterDrafts(
        BanterCategory.wildlifeTease,
        count: 20,
        destinationCode: 'OCALA',
      );
      expect(drafts.length, 20);
      expect(drafts.map((d) => d.text).toSet().length, 20,
          reason: 'lines are unique');
      expect(drafts.every((d) => d.category == BanterCategory.wildlifeTease),
          isTrue);
      expect(drafts.every((d) => d.destinationCode == 'OCALA'), isTrue);
      expect(drafts.every((d) => d.status == BanterStatus.draft), isTrue);
    });
  });

  group('GpsBanterDirector.eligible', () {
    final director = GpsBanterDirector(random: Random(1));

    test('only published, matching-category clips are eligible', () {
      final lib = [
        _clip('a', BanterCategory.welcome),
        _clip('b', BanterCategory.welcome, status: BanterStatus.draft),
        _clip('c', BanterCategory.arrival),
      ];
      final e = director.eligible(
          lib, BanterCategory.welcome, const GpsBanterContext(), BanterTrip());
      expect(e.map((c) => c.id), ['a']);
    });

    test('destination-targeted clips only match the current destination', () {
      final lib = [
        _clip('ocala', BanterCategory.welcome, dest: 'OCALA'),
        _clip('wekiwa', BanterCategory.welcome, dest: 'WEKIWA'),
        _clip('anywhere', BanterCategory.welcome),
      ];
      final e = director.eligible(
        lib,
        BanterCategory.welcome,
        const GpsBanterContext(destinationCode: 'OCALA', park: 'Ocala'),
        BanterTrip(),
      );
      expect(e.map((c) => c.id).toSet(), {'ocala', 'anywhere'});
    });

    test('guide mode filters clips', () {
      final lib = [
        _clip('kids', BanterCategory.welcome, guide: 'kids'),
        _clip('any', BanterCategory.welcome),
      ];
      final e = director.eligible(
        lib,
        BanterCategory.welcome,
        const GpsBanterContext(guideMode: 'naturalist'),
        BanterTrip(),
      );
      expect(e.map((c) => c.id).toSet(), {'any'});
    });
  });

  group('GpsBanterDirector.pick (cooldown + never repeat in trip)', () {
    test('never repeats a clip within a trip; recycles after exhaustion', () {
      final director = GpsBanterDirector(random: Random(3));
      final lib = [
        for (var i = 0; i < 4; i++) _clip('w$i', BanterCategory.welcome),
      ];
      final trip = BanterTrip();
      const ctx = GpsBanterContext();
      final picks = <String>[];
      for (var i = 0; i < 4; i++) {
        picks.add(director.pick(lib, BanterCategory.welcome, ctx, trip)!.clip.id);
      }
      expect(picks.toSet().length, 4, reason: 'all unique within the trip');
      expect(trip.tripCount, 0);
      // 5th pick exhausts the pool → new trip starts, still returns a clip.
      final fifth = director.pick(lib, BanterCategory.welcome, ctx, trip);
      expect(fifth, isNotNull);
      expect(trip.tripCount, 1);
    });

    test('returns null when the category has no clips', () {
      final director = GpsBanterDirector(random: Random(1));
      final sel = director.pick(
        [_clip('a', BanterCategory.arrival)],
        BanterCategory.welcome,
        const GpsBanterContext(),
        BanterTrip(),
      );
      expect(sel, isNull);
    });

    test('cooldown avoids a recently played clip across a trip reset', () {
      final director = GpsBanterDirector(random: Random(1));
      final lib = [
        _clip('a', BanterCategory.stationId),
        _clip('b', BanterCategory.stationId),
      ];
      final trip = BanterTrip(recentWindow: 4);
      const ctx = GpsBanterContext();
      final first =
          director.pick(lib, BanterCategory.stationId, ctx, trip)!.clip.id;
      // Force a new trip immediately; the just-played clip is still "recent".
      trip.startNewTrip();
      final next =
          director.pick(lib, BanterCategory.stationId, ctx, trip)!.clip.id;
      expect(next, isNot(first),
          reason: 'the recently played clip is skipped by cooldown');
    });

    test('pick fills the GPS placeholders and reports the transition', () {
      final director = GpsBanterDirector(random: Random(1));
      final lib = [
        _clip('h', BanterCategory.historyTease,
            text: 'History near {upcoming_attraction} is coming up.'),
      ];
      const ctx = GpsBanterContext(upcomingAttraction: 'Fort King');
      final sel = director.pick(lib, BanterCategory.historyTease, ctx, BanterTrip())!;
      expect(sel.text, contains('Fort King'));
      expect(sel.transition, BanterTransition.historyNarration);
    });
  });

  group('GpsBanterDirector.pickAny', () {
    test('picks the first category in priority order that has a clip', () {
      final director = GpsBanterDirector(random: Random(1));
      final lib = [
        _clip('fact', BanterCategory.interestingFact),
        _clip('scenic', BanterCategory.scenicObservation),
      ];
      final sel = director.pickAny(
        lib,
        [
          BanterCategory.wildlifeTease, // none
          BanterCategory.interestingFact, // present → wins
          BanterCategory.scenicObservation,
        ],
        const GpsBanterContext(),
        BanterTrip(),
      );
      expect(sel!.clip.category, BanterCategory.interestingFact);
    });
  });

  group('BanterTrip bookkeeping', () {
    test('markPlayed tracks the four signals + recent window', () {
      final trip = BanterTrip(recentWindow: 2);
      final now = DateTime(2026, 7, 28, 12);
      final a = _clip('a', BanterCategory.welcome, dest: 'OCALA');
      trip.markPlayed(a, now: now);
      trip.markPlayed(a, now: now);
      expect(trip.playCount['a'], 2);
      expect(trip.lastPlayed['a'], now);
      expect(trip.destinationPlays('OCALA'), 2);
      expect(trip.playedThisTrip('a'), isTrue);

      trip.markPlayed(_clip('b', BanterCategory.welcome), now: now);
      trip.markPlayed(_clip('c', BanterCategory.welcome), now: now);
      expect(trip.recent.length, 2, reason: 'recent window is trimmed');
      expect(trip.recent, ['c', 'b']);
    });

    test('startNewTrip clears trip-played but keeps lifetime counts', () {
      final trip = BanterTrip();
      trip.markPlayed(_clip('a', BanterCategory.welcome));
      trip.startNewTrip();
      expect(trip.playedThisTrip('a'), isFalse);
      expect(trip.playCount['a'], 1);
      expect(trip.tripCount, 1);
    });
  });
}
