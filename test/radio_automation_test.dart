import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/radio_automation/models/radio_schedule_rule.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_segment.dart';

void main() {
  test('SegmentCategory maps every requested category value', () {
    const expected = [
      'DJ_BANTER', 'SONG_INTRO', 'SONG_OUTRO', 'STATION_ID', 'PROMO',
      'WEATHER', 'SAFETY', 'GPS_TRANSITION', 'WILDLIFE_INTRO',
    ];
    for (final v in expected) {
      expect(SegmentCategory.fromDb(v).dbValue, v, reason: v);
    }
    expect(SegmentCategory.fromDb('nonsense'), SegmentCategory.djBanter);
  });

  test('TriggerType covers the full set with needsValue on the "every X" ones',
      () {
    expect(TriggerType.values.length, 16);
    expect(TriggerType.everyXSongs.needsValue, isTrue);
    expect(TriggerType.everyXMinutes.needsValue, isTrue);
    expect(TriggerType.topOfHour.needsValue, isFalse);
    expect(TriggerType.fromDb('GPS_ARRIVAL'), TriggerType.gpsArrival);
    expect(TriggerType.fromDb('SUNSET'), TriggerType.sunset);
  });

  test('RadioSegment.fromJson parses and toInsert round-trips key fields', () {
    final s = RadioSegment.fromJson({
      'id': 'abc',
      'title': 'Casey outro',
      'category': 'SONG_OUTRO',
      'station': 'country',
      'voice': 'Country Casey',
      'voice_id': 'v1',
      'script': 'That was a great one.',
      'audio_url': 'https://cdn/x.mp3',
      'duration': 12,
      'published': true,
      'play_count': 4,
    });
    expect(s.category, SegmentCategory.songOutro);
    expect(s.station, 'country');
    expect(s.hasAudio, isTrue);
    expect(s.published, isTrue);
    expect(s.playCount, 4);

    final ins = s.toInsert();
    expect(ins['category'], 'SONG_OUTRO');
    expect(ins['station'], 'country');
    expect(ins['voice_id'], 'v1');
    expect(ins['published'], true);
    // Server-managed fields are not included.
    expect(ins.containsKey('id'), isFalse);
    expect(ins.containsKey('play_count'), isFalse);
  });

  test('RadioSegment without audio is not playable', () {
    final s = RadioSegment.fromJson({
      'id': '1',
      'title': 'Draft',
      'category': 'DJ_BANTER',
      'station': 'all',
      'published': false,
    });
    expect(s.hasAudio, isFalse);
  });

  test('RadioScheduleRule parses trigger + value + daypart', () {
    final r = RadioScheduleRule.fromJson({
      'id': 'r1',
      'name': 'Every 3 songs',
      'station': 'country',
      'trigger_type': 'EVERY_X_SONGS',
      'trigger_value': 3,
      'category': 'DJ_BANTER',
      'daypart': 'day',
      'priority': 2,
      'enabled': true,
    });
    expect(r.triggerType, TriggerType.everyXSongs);
    expect(r.triggerValue, 3);
    expect(r.daypart, Daypart.day);
    expect(r.priority, 2);
    final ins = r.toInsert();
    expect(ins['trigger_type'], 'EVERY_X_SONGS');
    expect(ins['trigger_value'], 3);
    expect(ins['daypart'], 'day');
  });
}
