import 'dart:math';

import 'package:explorer_os_mobile/features/radio/services/smart_music_rotation.dart';
import 'package:flutter_test/flutter_test.dart';

RotationSong _song(
  String id, {
  String? park,
  List<String> tags = const [],
  String? mood,
  MusicTempo? tempo,
  int? duration,
  double? popularity,
}) =>
    RotationSong(
      id: id,
      audioUrl: 'https://audio/$id.mp3',
      title: 'Song $id',
      park: park,
      tags: tags,
      mood: mood,
      tempo: tempo,
      durationSeconds: duration,
      popularity: popularity,
    );

List<RotationSong> _library(int n) =>
    [for (var i = 1; i <= n; i++) _song('$i', duration: 180)];

void main() {
  group('daypart + season helpers', () {
    test('daypart buckets by hour', () {
      expect(MusicDaypart.fromHour(8), MusicDaypart.morning);
      expect(MusicDaypart.fromHour(13), MusicDaypart.afternoon);
      expect(MusicDaypart.fromHour(19), MusicDaypart.evening);
      expect(MusicDaypart.fromHour(23), MusicDaypart.night);
    });

    test('season buckets by month', () {
      expect(MusicSeason.fromMonth(4), MusicSeason.spring);
      expect(MusicSeason.fromMonth(7), MusicSeason.summer);
      expect(MusicSeason.fromMonth(10), MusicSeason.fall);
      expect(MusicSeason.fromMonth(1), MusicSeason.winter);
    });

    test('tempo preference varies by daypart', () {
      expect(tempoForDaypart(MusicDaypart.afternoon), MusicTempo.fast);
      expect(tempoForDaypart(MusicDaypart.night), MusicTempo.slow);
    });
  });

  group('scoreSong dimensions (deterministic, jitter=0)', () {
    final engine = SmartMusicRotationEngine(random: Random(1));

    test('park match adds points', () {
      const ctx = RotationContext(park: 'ocala');
      final match = engine.scoreSong(_song('a', park: 'ocala'), ctx);
      final noMatch = engine.scoreSong(_song('b', park: 'wekiwa'), ctx);
      expect(match, greaterThan(noMatch));
    });

    test('nearby attraction tag overlap adds points (capped)', () {
      const ctx = RotationContext(nearbyCategories: ['spring', 'trail']);
      final overlap = engine.scoreSong(_song('a', tags: ['spring']), ctx);
      final none = engine.scoreSong(_song('b', tags: ['history']), ctx);
      expect(overlap, greaterThan(none));
    });

    test('guide mode matches mood', () {
      const ctx = RotationContext(guideMode: 'calm');
      final match = engine.scoreSong(_song('a', mood: 'calm'), ctx);
      final none = engine.scoreSong(_song('b', mood: 'energetic'), ctx);
      expect(match, greaterThan(none));
    });

    test('time of day boosts matching tempo', () {
      const ctx = RotationContext(daypart: MusicDaypart.afternoon);
      final fast = engine.scoreSong(_song('a', tempo: MusicTempo.fast), ctx);
      final slow = engine.scoreSong(_song('b', tempo: MusicTempo.slow), ctx);
      expect(fast, greaterThan(slow));
    });

    test('season tag boosts', () {
      const ctx = RotationContext(season: MusicSeason.summer);
      final summer = engine.scoreSong(_song('a', tags: ['summer']), ctx);
      final none = engine.scoreSong(_song('b', tags: ['blues']), ctx);
      expect(summer, greaterThan(none));
    });

    test('duration fit rewards comfortable length, penalizes extremes', () {
      const ctx = RotationContext();
      final good = engine.scoreSong(_song('a', duration: 200), ctx);
      final tooLong = engine.scoreSong(_song('b', duration: 1200), ctx);
      expect(good, greaterThan(tooLong));
    });

    test('popularity adds points', () {
      const ctx = RotationContext();
      final pop = engine.scoreSong(_song('a', popularity: 1.0), ctx);
      final unpop = engine.scoreSong(_song('b', popularity: 0.0), ctx);
      expect(pop, greaterThan(unpop));
    });
  });

  group('temporary post-play score reduction', () {
    test('a recently played song scores lower than a fresh twin', () {
      final engine = SmartMusicRotationEngine(random: Random(1));
      const ctx = RotationContext();
      engine.tracker.markPlayed('a');
      final recent = engine.scoreSong(_song('a', duration: 180), ctx);
      final fresh = engine.scoreSong(_song('b', duration: 180), ctx);
      expect(recent, lessThan(fresh));
    });

    test('cooldown decays as the song slides out of the recent window', () {
      final engine = SmartMusicRotationEngine(random: Random(1), recentWindow: 3);
      const ctx = RotationContext();
      engine.tracker
        ..markPlayed('a') // recent index 2 after two more
        ..markPlayed('b')
        ..markPlayed('c');
      // 'c' just played (index 0) should be penalized more than 'a' (index 2).
      final justPlayed = engine.scoreSong(_song('c'), ctx);
      final older = engine.scoreSong(_song('a'), ctx);
      expect(justPlayed, lessThan(older));
    });

    test('overplayed songs are penalized', () {
      final engine = SmartMusicRotationEngine(random: Random(1));
      const ctx = RotationContext();
      for (var i = 0; i < 5; i++) {
        engine.tracker.markPlayed('a');
      }
      // Clear recent so only the overplay penalty remains.
      engine.tracker.recent.clear();
      final over = engine.scoreSong(_song('a'), ctx);
      final fresh = engine.scoreSong(_song('b'), ctx);
      expect(over, lessThan(fresh));
    });
  });

  group('scoring drives ranking (top-scoring, not sequential)', () {
    test('a strongly-relevant late song outranks an unrelated first song', () {
      final engine = SmartMusicRotationEngine(random: Random(3));
      const ctx = RotationContext(park: 'ocala', season: MusicSeason.summer);
      final songs = [
        _song('unrelated', park: 'other'),
        _song('unrelated2', park: 'other'),
        _song('relevant',
            park: 'ocala', tags: ['summer'], popularity: 1.0, duration: 180),
      ];
      final ranked = engine.scoredCandidates(songs, ctx);
      expect(ranked.first.song.id, 'relevant');
    });
  });

  group('no repeats during a trip', () {
    test('every song plays once before any repeats', () {
      final engine = SmartMusicRotationEngine(random: Random(7));
      final songs = _library(6);
      const ctx = RotationContext();
      final picks = [
        for (var i = 0; i < 6; i++) engine.pickNext(songs, ctx)!.id,
      ];
      expect(picks.toSet().length, 6, reason: 'no repeats within the trip');
    });

    test('trip resets after the library is exhausted', () {
      final engine = SmartMusicRotationEngine(random: Random(7));
      final songs = _library(3);
      const ctx = RotationContext();
      for (var i = 0; i < 3; i++) {
        engine.pickNext(songs, ctx);
      }
      expect(engine.tracker.tripCount, 0);
      // 4th pick exhausts the pool → a fresh trip starts and returns a song.
      final next = engine.pickNext(songs, ctx);
      expect(next, isNotNull);
      expect(engine.tracker.tripCount, 1);
    });

    test('pickNext never returns a song already played this trip', () {
      final engine = SmartMusicRotationEngine(random: Random(11));
      final songs = _library(5);
      const ctx = RotationContext();
      final seen = <String>{};
      for (var i = 0; i < 5; i++) {
        final id = engine.pickNext(songs, ctx)!.id;
        expect(seen.contains(id), isFalse);
        seen.add(id);
      }
    });
  });

  group('never the same order twice', () {
    test('different seeds produce different orderings', () {
      final songs = _library(8);
      const ctx = RotationContext();
      List<String> trip(int seed) {
        final e = SmartMusicRotationEngine(random: Random(seed));
        return [for (var i = 0; i < 8; i++) e.pickNext(songs, ctx)!.id];
      }

      final a = trip(1);
      final b = trip(2);
      expect(a, isNot(equals(b)),
          reason: 'a fresh seed each drive yields a fresh order');
    });

    test('same seed is reproducible (deterministic for tests)', () {
      final songs = _library(8);
      const ctx = RotationContext();
      List<String> trip(int seed) {
        final e = SmartMusicRotationEngine(random: Random(seed));
        return [for (var i = 0; i < 8; i++) e.pickNext(songs, ctx)!.id];
      }

      expect(trip(5), equals(trip(5)));
    });

    test('selection is not strictly sequential', () {
      final songs = _library(8);
      const ctx = RotationContext();
      final e = SmartMusicRotationEngine(random: Random(9));
      final order = [for (var i = 0; i < 8; i++) e.pickNext(songs, ctx)!.id];
      final sequential = [for (final s in songs) s.id];
      expect(order, isNot(equals(sequential)));
    });
  });

  group('tracker bookkeeping', () {
    test('markPlayed records play_count, last_played, park_played', () {
      final t = RotationTracker();
      final now = DateTime(2026, 7, 28, 12);
      t.markPlayed('a', park: 'ocala', now: now);
      t.markPlayed('a', park: 'ocala', now: now);
      expect(t.playCount['a'], 2);
      expect(t.lastPlayed['a'], now);
      expect(t.parkPlayCount('ocala', 'a'), 2);
      expect(t.playedThisTrip('a'), isTrue);
    });

    test('startNewTrip clears trip-played but keeps counts + recent', () {
      final t = RotationTracker();
      t.markPlayed('a');
      t.startNewTrip();
      expect(t.playedThisTrip('a'), isFalse);
      expect(t.playCount['a'], 1);
      expect(t.recent, contains('a'));
      expect(t.tripCount, 1);
    });
  });

  test('empty library returns null', () {
    final engine = SmartMusicRotationEngine(random: Random(1));
    expect(engine.pickNext(const [], const RotationContext()), isNull);
  });
}
