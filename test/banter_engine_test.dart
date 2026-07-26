import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/dj/models/dj_personality.dart';

void main() {
  test('fill substitutes placeholders from context', () {
    const ctx = BanterContext(
      station: 'Ocala National Forest Radio',
      park: 'Ocala National Forest',
      songTitle: 'Rolling Through the Pines',
      artist: 'Country Casey',
      landmark: 'Juniper Springs',
      wildlife: 'white-tailed deer',
    );
    final out = BanterEngine.fill(
      'That was "{song_title}". Near {landmark}, watch for {wildlife}.',
      ctx,
    );
    expect(out,
        'That was "Rolling Through the Pines". Near Juniper Springs, watch for white-tailed deer.');
  });

  test('fill uses natural fallbacks for missing fields', () {
    const ctx = BanterContext();
    final out = BanterEngine.fill(
        'Up next: "{song_title}" by {artist} near {landmark}.', ctx);
    expect(out, 'Up next: "that track" by a local artist near the road ahead.');
    expect(out.contains('{'), isFalse); // no leftover placeholders
  });

  test('generate returns a filled line for a station+situation', () {
    final engine = BanterEngine(rng: Random(1));
    final line = engine.generate(
      DjStation.country,
      BanterSituation.songIntro,
      const BanterContext(songTitle: 'Backroad Hymn'),
    );
    expect(line, isNotNull);
    expect(line!.contains('{'), isFalse);
    expect(line.toLowerCase(), contains('backroad hymn'.toLowerCase()));
  });

  test('song intros rotate (same song, different lines across seeds)', () {
    const ctx = BanterContext(songTitle: 'Backroad Hymn', artist: 'Casey');
    final outputs = <String>{};
    for (var seed = 0; seed < 40; seed++) {
      final line = BanterEngine(rng: Random(seed))
          .songIntro(DjStation.country, ctx);
      if (line != null) outputs.add(line);
    }
    // Country pulls from its own + the shared song-intro pool → variety.
    expect(outputs.length, greaterThan(1));
  });

  test('country station pulls both country-specific and shared templates', () {
    final engine = BanterEngine();
    final pool =
        engine.templatesFor(DjStation.country, BanterSituation.songIntro);
    expect(pool.any((t) => t.station == DjStation.country), isTrue);
    expect(pool.any((t) => t.station == DjStation.all), isTrue);
  });

  test('every situation has at least one template', () {
    final engine = BanterEngine();
    for (final s in BanterSituation.values) {
      final pool = engine.templatesFor(DjStation.all, s);
      expect(pool, isNotEmpty, reason: s.label);
    }
  });

  test('seed roster covers the six DJs and maps stations', () {
    expect(kSeedDjs, hasLength(6));
    final country = djForStation(kSeedDjs, DjStation.country);
    expect(country.name, 'Country Casey');
    final rock = djForStation(kSeedDjs, DjStation.rock);
    expect(rock.name, 'Rock Rob');
  });
}
