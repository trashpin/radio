import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/services/dj_banter_scheduler.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_schedule_rule.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_segment.dart';
import 'package:explorer_os_mobile/features/radio_automation/services/automation_engine.dart';

RadioScheduleRule rule(
  TriggerType trigger, {
  String station = 'all',
  String category = 'STATION_ID',
  int? value,
  Daypart daypart = Daypart.any,
  int priority = 5,
  bool enabled = true,
}) =>
    RadioScheduleRule(
      id: '$trigger$priority',
      name: '$trigger',
      station: station,
      triggerType: trigger,
      category: category,
      triggerValue: value,
      daypart: daypart,
      priority: priority,
      enabled: enabled,
    );

RadioSegment seg(
  String id,
  SegmentCategory category, {
  String station = 'all',
  bool published = true,
  String? audioUrl,
}) =>
    RadioSegment(
      id: id,
      title: id,
      category: category,
      station: station,
      audioUrl: audioUrl ?? 'https://cdn/$id.mp3',
      published: published,
    );

void main() {
  final engine = AutomationEngine(rng: Random(1));
  final daytime = DateTime(2026, 7, 26, 12, 0); // noon
  final night = DateTime(2026, 7, 26, 23, 0);

  test('EVERY_X_SONGS fires only on multiples of N', () {
    final rules = [rule(TriggerType.everyXSongs, value: 3)];
    final segs = [seg('id1', SegmentCategory.stationId)];
    expect(engine.onSong(rules, segs, station: DjStation.all, songIndex: 1, now: daytime), isNull);
    expect(engine.onSong(rules, segs, station: DjStation.all, songIndex: 2, now: daytime), isNull);
    expect(engine.onSong(rules, segs, station: DjStation.all, songIndex: 3, now: daytime), isNotNull);
    expect(engine.onSong(rules, segs, station: DjStation.all, songIndex: 6, now: daytime), isNotNull);
  });

  test('AFTER_SONG fires every boundary and picks its category', () {
    final rules = [rule(TriggerType.afterSong, category: 'PROMO')];
    final segs = [seg('promo1', SegmentCategory.promo), seg('id1', SegmentCategory.stationId)];
    final chosen = engine.onSong(rules, segs, station: DjStation.all, songIndex: 1, now: daytime);
    expect(chosen, isNotNull);
    expect(chosen!.category, SegmentCategory.promo);
  });

  test('daypart gating: a day-only rule does not fire at night', () {
    final rules = [rule(TriggerType.afterSong, daypart: Daypart.day)];
    final segs = [seg('id1', SegmentCategory.stationId)];
    expect(engine.onSong(rules, segs, station: DjStation.all, songIndex: 1, now: daytime), isNotNull);
    expect(engine.onSong(rules, segs, station: DjStation.all, songIndex: 1, now: night), isNull);
  });

  test('priority: lower number wins', () {
    final rules = [
      rule(TriggerType.afterSong, category: 'PROMO', priority: 9),
      rule(TriggerType.afterSong, category: 'STATION_ID', priority: 1),
    ];
    final segs = [seg('p', SegmentCategory.promo), seg('s', SegmentCategory.stationId)];
    final chosen = engine.onSong(rules, segs, station: DjStation.all, songIndex: 1, now: daytime);
    expect(chosen!.category, SegmentCategory.stationId); // priority 1 rule
  });

  test('station filtering: country rule ignored on rock station', () {
    final rules = [rule(TriggerType.afterSong, station: 'country')];
    final segs = [seg('id1', SegmentCategory.stationId, station: 'country')];
    expect(engine.onSong(rules, segs, station: DjStation.rock, songIndex: 1, now: daytime), isNull);
    expect(engine.onSong(rules, segs, station: DjStation.country, songIndex: 1, now: daytime), isNotNull);
  });

  test('no published segment for the category → null', () {
    final rules = [rule(TriggerType.afterSong, category: 'WEATHER')];
    final segs = [seg('id1', SegmentCategory.stationId)]; // no WEATHER segment
    expect(engine.onSong(rules, segs, station: DjStation.all, songIndex: 1, now: daytime), isNull);
  });

  test('onTick TOP_OF_HOUR fires at :00 only', () {
    final rules = [rule(TriggerType.topOfHour)];
    final segs = [seg('id1', SegmentCategory.stationId)];
    expect(engine.onTick(rules, segs, station: DjStation.all, sessionMinutes: 5, now: DateTime(2026, 7, 26, 15, 0)), isNotNull);
    expect(engine.onTick(rules, segs, station: DjStation.all, sessionMinutes: 5, now: DateTime(2026, 7, 26, 15, 12)), isNull);
  });

  test('onTick EVERY_X_MINUTES fires on multiples of N minutes elapsed', () {
    final rules = [rule(TriggerType.everyXMinutes, value: 20)];
    final segs = [seg('id1', SegmentCategory.stationId)];
    expect(engine.onTick(rules, segs, station: DjStation.all, sessionMinutes: 20, now: daytime), isNotNull);
    expect(engine.onTick(rules, segs, station: DjStation.all, sessionMinutes: 25, now: daytime), isNull);
  });

  test('scheduler prefers rule-driven segment (its own audio) over default banter',
      () {
    final s = DjBanterScheduler(everyNSongs: 99, rng: Random(0)); // default rarely fires
    s.setAutomation(
      AutomationEngine(rng: Random(0)),
      [rule(TriggerType.afterSong, category: 'PROMO')],
      [seg('promo1', SegmentCategory.promo)],
    );
    final out = s.onMusicPlayed(
      const AudioSegment(
          id: 'song', title: 'Song', type: AudioSegmentType.music, priority: PlaybackPriority.music),
      radioStationName: 'Country Roads Radio',
    );
    expect(out, isNotNull);
    expect(out!.audioUrl, 'https://cdn/promo1.mp3');
    expect(out.type, AudioSegmentType.announcement);
  });
}
