import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/services/dj_banter_scheduler.dart';

AudioSegment song(String title, {String? artist}) => AudioSegment(
      id: 'song:$title',
      title: title,
      artist: artist,
      type: AudioSegmentType.music,
      priority: PlaybackPriority.music,
    );

void main() {
  test('maps radio station names to DJ station flavors', () {
    expect(DjBanterScheduler.stationFor('Country Roads Radio'), DjStation.country);
    expect(DjBanterScheduler.stationFor('Rock the Forest'), DjStation.rock);
    expect(DjBanterScheduler.stationFor('Top Hits'), DjStation.topHits);
    expect(DjBanterScheduler.stationFor('Kids Time'), DjStation.kids);
    expect(DjBanterScheduler.stationFor('Ocala National Forest Radio'),
        DjStation.all);
  });

  test('only talks every N songs', () {
    final s = DjBanterScheduler(everyNSongs: 3, rng: Random(1));
    expect(s.onMusicPlayed(song('A')), isNull); // 1
    expect(s.onMusicPlayed(song('B')), isNull); // 2
    expect(s.onMusicPlayed(song('C')), isNotNull); // 3 → talks
    expect(s.onMusicPlayed(song('D')), isNull); // 4
  });

  test('disabled scheduler never talks', () {
    final s = DjBanterScheduler(everyNSongs: 1, enabled: false);
    expect(s.onMusicPlayed(song('A')), isNull);
  });

  test('produces a spoken announcement segment (no audio URL, no placeholders)',
      () {
    final s = DjBanterScheduler(everyNSongs: 1, rng: Random(2));
    final seg = s.onMusicPlayed(song('Rolling Through the Pines',
        artist: 'Casey'),
        radioStationName: 'Country Roads Radio');
    expect(seg, isNotNull);
    expect(seg!.spokenText, isNotNull);
    expect(seg.spokenText!.trim(), isNotEmpty);
    expect(seg.spokenText!.contains('{'), isFalse);
    expect(seg.audioUrl, isNull);
    expect(seg.type, AudioSegmentType.announcement);
    expect(seg.priority, PlaybackPriority.scheduledAnnouncement);
    expect(seg.id.startsWith('dj:'), isTrue);
  });

  test('banter references the finished song across rotations', () {
    var mentioned = false;
    for (var seed = 0; seed < 50 && !mentioned; seed++) {
      final s = DjBanterScheduler(everyNSongs: 1, rng: Random(seed));
      final seg = s.onMusicPlayed(song('Backroad Hymn'),
          radioStationName: 'Country Roads Radio');
      if (seg?.spokenText?.contains('Backroad Hymn') ?? false) mentioned = true;
    }
    expect(mentioned, isTrue);
  });
}
