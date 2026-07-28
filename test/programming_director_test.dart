import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/programming_director/programming_director.dart';

ProgrammingAsset _a(ProgrammingSlotType t, String id) => ProgrammingAsset(
      id: id,
      title: id,
      audioUrl: 'https://cdn/$id.mp3',
      slotType: t,
      source: t.name,
    );

void main() {
  const director = ProgrammingDirector();

  Map<ProgrammingSlotType, List<ProgrammingAsset>> fullPools() => {
        ProgrammingSlotType.djWelcome: [_a(ProgrammingSlotType.djWelcome, 'dj1')],
        ProgrammingSlotType.stationId: [_a(ProgrammingSlotType.stationId, 'id1')],
        ProgrammingSlotType.songIntro: [_a(ProgrammingSlotType.songIntro, 'in1')],
        ProgrammingSlotType.song: [
          _a(ProgrammingSlotType.song, 'song1'),
          _a(ProgrammingSlotType.song, 'song2'),
        ],
        ProgrammingSlotType.songOutro: [_a(ProgrammingSlotType.songOutro, 'out1')],
        ProgrammingSlotType.historyTease: [_a(ProgrammingSlotType.historyTease, 'ht1')],
        ProgrammingSlotType.arrival: [_a(ProgrammingSlotType.arrival, 'arr1')],
        ProgrammingSlotType.history: [_a(ProgrammingSlotType.history, 'his1')],
        ProgrammingSlotType.music: [_a(ProgrammingSlotType.music, 'm1')],
        ProgrammingSlotType.wildlife: [_a(ProgrammingSlotType.wildlife, 'wl1')],
      };

  test('walks the clock in order', () {
    final pools = fullPools();
    var pos = 0;
    final seq = <ProgrammingSlotType>[];
    final played = <String>{};
    for (var i = 0; i < 5; i++) {
      final r = director.next(ProgrammingContext(
          clock: ProgrammingClock.station,
          position: pos,
          pools: pools,
          playedKeys: played));
      seq.add(r.slotType!);
      played.add(r.asset!.key);
      pos = r.nextPosition;
    }
    expect(seq.take(5).toList(), [
      ProgrammingSlotType.djWelcome,
      ProgrammingSlotType.stationId,
      ProgrammingSlotType.songIntro,
      ProgrammingSlotType.song,
      ProgrammingSlotType.songOutro,
    ]);
  });

  test('reuses existing assets and does not repeat until recycled', () {
    // Two songs; the song slot appears multiple times in the clock.
    final pools = fullPools();
    final played = <String>{};
    // First song slot (position 3).
    final r1 = director.next(ProgrammingContext(
        clock: ProgrammingClock.station, position: 3, pools: pools, playedKeys: played));
    expect(r1.asset!.id, 'song1');
    played.add(r1.asset!.key);
    // Next song slot (position 6).
    final r2 = director.next(ProgrammingContext(
        clock: ProgrammingClock.station, position: 6, pools: pools, playedKeys: played));
    expect(r2.asset!.id, 'song2'); // fresh, not repeated
    played.add(r2.asset!.key);
    // Third song slot → both played → recycle.
    final r3 = director.next(ProgrammingContext(
        clock: ProgrammingClock.station, position: 12, pools: pools, playedKeys: played));
    expect(r3.reason, 'recycled');
    expect(['song1', 'song2'], contains(r3.asset!.id));
  });

  test('skips empty slots to the next available asset', () {
    // Only station + song pools exist; djWelcome/songIntro empty.
    final pools = {
      ProgrammingSlotType.stationId: [_a(ProgrammingSlotType.stationId, 'id1')],
      ProgrammingSlotType.song: [_a(ProgrammingSlotType.song, 'song1')],
    };
    // Position 0 = djWelcome (empty) → should skip to stationId.
    final r = director.next(ProgrammingContext(
        clock: ProgrammingClock.station, position: 0, pools: pools));
    expect(r.slotType, ProgrammingSlotType.stationId);
    expect(r.asset!.id, 'id1');
  });

  test('falls back to music when the walked slots are empty', () {
    final pools = {
      ProgrammingSlotType.music: [_a(ProgrammingSlotType.music, 'm1')],
    };
    // Start at djWelcome; nothing until it loops → music fill.
    final r = director.next(ProgrammingContext(
        clock: ProgrammingClock.station, position: 0, pools: pools));
    expect(r.asset!.id, 'm1');
  });

  test('no assets at all → silent (no crash)', () {
    final r = director.next(const ProgrammingContext(
        clock: ProgrammingClock.station, position: 0, pools: {}));
    expect(r.hasAsset, isFalse);
    expect(r.reason, 'no assets');
  });
}
