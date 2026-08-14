import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio_scheduler/controllers/rundown_playback_controller.dart';
import 'package:explorer_os_mobile/features/radio_scheduler/models/rundown.dart';

RundownItem _item(
  String id,
  RundownItemType type, {
  int seconds = 0,
  bool enabled = true,
  String? audioUrl,
  String? script,
  String name = '',
}) =>
    RundownItem(
      id: id,
      rundownId: 'r1',
      type: type,
      sortOrder: 0,
      name: name,
      durationSeconds: seconds,
      enabled: enabled,
      audioUrl: audioUrl,
      script: script,
    );

void main() {
  group('RundownItemType', () {
    test('exposes all 11 rundown item types', () {
      expect(RundownItemType.values.length, 11);
      expect(
        RundownItemType.values.map((t) => t.id).toSet(),
        {
          'music',
          'dj_banter',
          'station_id',
          'sweeper',
          'local_fact',
          'history',
          'weather',
          'event',
          'location_story',
          'custom_audio',
          'silence',
        },
      );
    });

    test('fromId round-trips and falls back to custom_audio', () {
      expect(RundownItemType.fromId('weather'), RundownItemType.weather);
      expect(RundownItemType.fromId('nope'), RundownItemType.customAudio);
    });
  });

  group('RundownItem', () {
    test('effectiveSeconds falls back to the type default', () {
      expect(_item('a', RundownItemType.music).effectiveSeconds,
          RundownItemType.music.defaultSeconds);
      expect(_item('a', RundownItemType.music, seconds: 42).effectiveSeconds, 42);
    });

    test('isPlayable: silence always, others need audio or script', () {
      expect(_item('s', RundownItemType.silence).isPlayable, isTrue);
      expect(_item('m', RundownItemType.music).isPlayable, isFalse);
      expect(_item('m', RundownItemType.music, audioUrl: 'u').isPlayable, isTrue);
      expect(_item('f', RundownItemType.localFact, script: 'hi').isPlayable,
          isTrue);
    });

    test('displayName falls back to the type label', () {
      expect(_item('a', RundownItemType.weather).displayName, 'Weather');
      expect(_item('a', RundownItemType.weather, name: 'Marion forecast')
          .displayName, 'Marion forecast');
    });
  });

  group('computeRundownTimeline', () {
    test('lays enabled items back-to-back and skips disabled', () {
      final items = [
        _item('a', RundownItemType.stationId, seconds: 10),
        _item('b', RundownItemType.music, seconds: 180, enabled: false),
        _item('c', RundownItemType.weather, seconds: 20),
      ];
      final slots = computeRundownTimeline(items);
      expect(slots.length, 2); // disabled 'b' excluded
      expect(slots[0].item.id, 'a');
      expect(slots[0].startOffset, 0);
      expect(slots[0].endOffset, 10);
      // 'c' starts right after 'a' (the disabled music adds no time).
      expect(slots[1].item.id, 'c');
      expect(slots[1].startOffset, 10);
      expect(slots[1].endOffset, 30);
    });

    test('computes wall-clock times when a start is given', () {
      final start = DateTime(2026, 1, 1, 9, 0, 0);
      final slots = computeRundownTimeline(
        [_item('a', RundownItemType.stationId, seconds: 60)],
        start: start,
      );
      expect(slots.single.startClock, start);
      expect(slots.single.endClock, start.add(const Duration(seconds: 60)));
    });
  });

  group('formatClockSeconds', () {
    test('formats mm:ss and clamps negatives', () {
      expect(formatClockSeconds(0), '00:00');
      expect(formatClockSeconds(9), '00:09');
      expect(formatClockSeconds(75), '01:15');
      expect(formatClockSeconds(-5), '00:00');
    });
  });

  group('rundownItemToSegment (adapter → existing audio engine)', () {
    test('music/custom audio with a URL becomes a playable segment', () {
      final seg = rundownItemToSegment(
        _item('m', RundownItemType.music, audioUrl: 'https://a/x.mp3'),
        segId: 'seg1',
      );
      expect(seg, isNotNull);
      expect(seg!.audioUrl, 'https://a/x.mp3');
      expect(seg.spokenText, isNull);
      expect(seg.type, AudioSegmentType.music);
    });

    test('script-only item becomes a spoken (TTS) segment', () {
      final seg = rundownItemToSegment(
        _item('f', RundownItemType.localFact, script: 'Fun fact.'),
        segId: 'seg2',
      );
      expect(seg, isNotNull);
      expect(seg!.spokenText, 'Fun fact.');
      expect(seg.audioUrl, isNull);
    });

    test('audio wins over script when both are present', () {
      final seg = rundownItemToSegment(
        _item('h', RundownItemType.history,
            audioUrl: 'https://a/h.mp3', script: 'ignored'),
        segId: 'seg3',
      );
      expect(seg!.audioUrl, 'https://a/h.mp3');
      expect(seg.spokenText, isNull);
    });

    test('silence returns null (a timed gap, handled by the controller)', () {
      expect(
        rundownItemToSegment(_item('s', RundownItemType.silence), segId: 'x'),
        isNull,
      );
    });

    test('unavailable item (no audio + no script) returns null → skipped', () {
      expect(
        rundownItemToSegment(_item('m', RundownItemType.music), segId: 'x'),
        isNull,
      );
    });

    test('type maps to a sensible AudioSegmentType', () {
      AudioSegment segFor(RundownItemType t) => rundownItemToSegment(
            _item('i', t, script: 'x'),
            segId: 's',
          )!;
      expect(segFor(RundownItemType.stationId).type,
          AudioSegmentType.stationIdentification);
      expect(segFor(RundownItemType.weather).type, AudioSegmentType.weather);
      expect(segFor(RundownItemType.event).type, AudioSegmentType.specialEvent);
      expect(segFor(RundownItemType.locationStory).type,
          AudioSegmentType.narration);
    });
  });

  group('RundownPlaybackState (now-playing math)', () {
    final items = [
      _item('a', RundownItemType.stationId, seconds: 10),
      _item('b', RundownItemType.music, seconds: 180),
      _item('c', RundownItemType.weather, seconds: 20),
    ];

    test('current/next/upcoming reflect the index', () {
      final s = RundownPlaybackState(items: items, index: 0, playing: true);
      expect(s.current!.id, 'a');
      expect(s.next!.id, 'b');
      expect(s.upcoming.map((i) => i.id).toList(), ['b', 'c']);
      expect(s.hasNext, isTrue);
    });

    test('remaining = duration - elapsed, clamped at zero; last item hasNext=false',
        () {
      final s = RundownPlaybackState(
          items: items, index: 2, playing: true, elapsedSeconds: 5);
      expect(s.current!.id, 'c');
      expect(s.next, isNull);
      expect(s.hasNext, isFalse);
      expect(s.remainingSeconds, 15); // 20 - 5

      final over = RundownPlaybackState(
          items: items, index: 0, playing: true, elapsedSeconds: 99);
      expect(over.remainingSeconds, 0);
    });

    test('active is true while playing or paused', () {
      expect(const RundownPlaybackState().active, isFalse);
      expect(RundownPlaybackState(items: items, index: 0, playing: true).active,
          isTrue);
      expect(RundownPlaybackState(items: items, index: 0, paused: true).active,
          isTrue);
    });
  });
}
