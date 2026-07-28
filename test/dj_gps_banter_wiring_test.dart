// Proves the DJ Banter Studio library is wired into the live between-song DJ:
// when a published, GPS-aware library is loaded, the scheduler prefers it, fills
// placeholders from the live context, records plays, and never repeats in a trip.

import 'dart:math';

import 'package:explorer_os_mobile/features/dj/banter_studio/banter_category.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/dj_banter_clip.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/gps_banter_director.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/services/dj_banter_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

const _song = AudioSegment(
  id: 'song:1',
  title: 'Backroad Hymn',
  type: AudioSegmentType.music,
  priority: PlaybackPriority.music,
);

DjBanterClip _clip(String id,
        {String text = 'Watch for {nearby_wildlife} near {park}.',
        BanterCategory cat = BanterCategory.wildlifeTease,
        String? audioUrl}) =>
    DjBanterClip(
      id: id,
      category: cat,
      text: text,
      status: BanterStatus.published,
      gpsRegion: 'Ocala National Forest',
      audioUrl: audioUrl,
    );

void main() {
  test('GPS library banter is preferred and fills the live context', () {
    final played = <String>[];
    final dj = DjBanterScheduler(everyNSongs: 1, rng: Random(1))
      ..setGpsBanter(
        director: GpsBanterDirector(random: Random(1)),
        trip: BanterTrip(),
        context: () => const GpsBanterContext(
          park: 'Ocala National Forest',
          nearbyWildlife: ['Florida black bears'],
        ),
        onPlayed: played.add,
      )
      ..setBanterLibrary([_clip('a')]);

    final seg = dj.onMusicPlayed(_song, radioStationName: 'Ocala Radio');
    expect(seg, isNotNull);
    expect(seg!.spokenText, contains('Florida black bears'));
    expect(seg.spokenText, contains('Ocala National Forest'));
    expect(seg.spokenText!.contains('{'), isFalse, reason: 'placeholders filled');
    expect(played, ['a'], reason: 'play recorded for the library clip');
  });

  test('voiced clips play their audio instead of TTS', () {
    final dj = DjBanterScheduler(everyNSongs: 1, rng: Random(1))
      ..setGpsBanter(
        director: GpsBanterDirector(random: Random(1)),
        trip: BanterTrip(),
        context: () => const GpsBanterContext(park: 'Ocala National Forest'),
      )
      ..setBanterLibrary([_clip('a', audioUrl: 'https://cdn/a.mp3')]);

    final seg = dj.onMusicPlayed(_song, radioStationName: 'Ocala Radio');
    expect(seg!.audioUrl, 'https://cdn/a.mp3');
    expect(seg.spokenText, isNull);
    expect(seg.priority, PlaybackPriority.scheduledAnnouncement);
  });

  test('never repeats a clip within a trip', () {
    final played = <String>[];
    final dj = DjBanterScheduler(everyNSongs: 1, rng: Random(2))
      ..setGpsBanter(
        director: GpsBanterDirector(random: Random(2)),
        trip: BanterTrip(),
        context: () => const GpsBanterContext(park: 'Ocala National Forest'),
        onPlayed: played.add,
      )
      ..setBanterLibrary([_clip('a'), _clip('b')]);

    dj.onMusicPlayed(_song, radioStationName: 'Ocala Radio');
    dj.onMusicPlayed(_song, radioStationName: 'Ocala Radio');
    expect(played.toSet().length, 2, reason: 'two distinct clips, no repeat');
  });

  test('falls back to template banter when no library is loaded', () {
    final dj = DjBanterScheduler(everyNSongs: 1, rng: Random(3));
    final seg = dj.onMusicPlayed(_song, radioStationName: 'Country Roads Radio');
    // Template banter still works (spoken text, no library clip).
    expect(seg?.spokenText, isNotNull);
  });
}
