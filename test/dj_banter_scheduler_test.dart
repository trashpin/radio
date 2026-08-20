import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/dj/models/dj_clip.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/services/dj_banter_scheduler.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_schedule_rule.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_segment.dart';
import 'package:explorer_os_mobile/features/radio_automation/services/announcement_content.dart';
import 'package:explorer_os_mobile/features/radio_automation/services/automation_engine.dart';

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

  test('prefers a pre-generated clip (DJ voice URL) over TTS when one matches',
      () {
    final s = DjBanterScheduler(everyNSongs: 1, rng: Random(0));
    s.setClips(const [
      DjClip(
        id: 'c1',
        station: DjStation.country,
        situation: BanterSituation.songOutro,
        audioUrl: 'https://cdn/dj/country/outro_0.mp3',
        voiceName: 'Country Casey',
      ),
      DjClip(
        id: 'c2',
        station: DjStation.all,
        situation: BanterSituation.stationId,
        audioUrl: 'https://cdn/dj/all/id_0.mp3',
        voiceName: 'Country Casey',
      ),
    ]);
    // Try several times; whichever situation is chosen, a clip should match
    // (songOutro→country clip, stationId→all clip), so we always get audio.
    for (var i = 0; i < 10; i++) {
      final seg = s.onMusicPlayed(song('X'), radioStationName: 'Country Roads Radio');
      expect(seg, isNotNull);
      expect(seg!.audioUrl, isNotNull, reason: 'should play the DJ-voice clip');
      expect(seg.spokenText, isNull);
      expect(seg.artist, 'Country Casey');
    }
  });

  test('falls back to TTS when no clip matches the station+situation', () {
    final s = DjBanterScheduler(everyNSongs: 1, rng: Random(0));
    s.setClips(const [
      DjClip(
        id: 'rockonly',
        station: DjStation.rock,
        situation: BanterSituation.songOutro,
        audioUrl: 'https://cdn/dj/rock/outro_0.mp3',
      ),
    ]);
    // Country station → no matching clip → spoken (TTS).
    final seg = s.onMusicPlayed(song('X'), radioStationName: 'Country Roads Radio');
    expect(seg, isNotNull);
    expect(seg!.audioUrl, isNull);
    expect(seg.spokenText, isNotNull);
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

  test('DJ banter engine fills a county fact template (Phase B)', () {
    final e = BanterEngine(rng: Random(1));
    for (var i = 0; i < 8; i++) {
      final s = e.generate(
        DjStation.all,
        BanterSituation.countyFact,
        const BanterContext(
            county: 'Marion', fact: 'It is the Horse Capital of the World.'),
      );
      expect(s, isNotNull);
      expect(s!, contains('It is the Horse Capital of the World.'));
      expect(s.contains('{'), isFalse);
    }
  });

  test('DJ shares an admin county fact when facts are set (Phase B)', () {
    final s = DjBanterScheduler(everyNSongs: 1, rng: Random(3))
      ..setCountyFacts(
          county: 'Marion',
          facts: const ['It is the Horse Capital of the World.']);
    String? found;
    for (var i = 0; i < 80 && found == null; i++) {
      final seg = s.onMusicPlayed(song('Song $i'));
      final t = seg?.spokenText;
      if (t != null && t.contains('Horse Capital of the World')) found = t;
    }
    expect(found, isNotNull, reason: 'a county fact should surface within 80 songs');
  });

  test('no county facts set → DJ never emits a county-fact segment', () {
    final s = DjBanterScheduler(everyNSongs: 1, rng: Random(3));
    for (var i = 0; i < 20; i++) {
      final seg = s.onMusicPlayed(song('Song $i'));
      expect(seg?.id.startsWith('djcounty:') ?? false, isFalse);
    }
  });

  test('automation drives a safety announcement with safety semantics (Step 2)',
      () {
    // The unified path: a legacy interval safety rule + the unified content
    // pool, evaluated by AutomationEngine on a time tick, must produce a
    // non-interruptible, resume-after safety warning (RadioScheduler parity).
    final s = DjBanterScheduler(everyNSongs: 1, rng: Random(1));
    final rule = legacyScheduleRuleToRule({
      'id': 'r1',
      'content_type': 'safety',
      'cadence': 'interval',
      'interval_minutes': 15,
      'active': true,
    })!;
    final segs = combineAnnouncementContent(safety: [
      {'id': 's1', 'title': 'Watch for bears', 'audio_url': 'https://a/s.mp3'}
    ]);
    s.setAutomation(AutomationEngine(rng: Random(1)), [rule], segs);

    final seg = s.onTick(radioStationName: null, sessionMinutes: 15);
    expect(seg, isNotNull);
    expect(seg!.type, AudioSegmentType.safetyWarning);
    expect(seg.priority, PlaybackPriority.safetyWarning);
    expect(seg.interruptible, isFalse);
    expect(seg.resumeAfter, isTrue);
    expect(seg.audioUrl, 'https://a/s.mp3');
  });

  test('a STATION_ID segment gets proper station-ID semantics — not the '
      'generic skippable-banter catch-all', () {
    final s = DjBanterScheduler(everyNSongs: 1, rng: Random(1));
    final rule = RadioScheduleRule(
      id: 'r1',
      name: 'Station ID',
      station: 'all',
      category: 'STATION_ID',
      triggerType: TriggerType.afterSong,
      priority: 1,
      enabled: true,
    );
    final segs = [
      RadioSegment(
        id: 'sid1',
        title: 'Sunshine Travel Radio ID',
        category: SegmentCategory.stationId,
        station: 'all',
        audioUrl: 'https://cdn/sid1.mp3',
        published: true,
      ),
    ];
    s.setAutomation(AutomationEngine(rng: Random(1)), [rule], segs);

    final seg = s.onMusicPlayed(song('Some Song'));
    expect(seg, isNotNull);
    expect(seg!.type, AudioSegmentType.stationIdentification);
    expect(seg.priority, PlaybackPriority.stationIdentification);
    expect(seg.interruptible, isFalse);
    expect(seg.resumeAfter, isTrue);
    expect(seg.audioUrl, 'https://cdn/sid1.mp3');
  });
}
