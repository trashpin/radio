import 'dart:math';

import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_schedule_rule.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_segment.dart';

/// Evaluates `radio_schedule_rules` against the current moment and picks a
/// published segment to play — the decision core of the automation "playback
/// engine".
///
/// PURE + deterministic when seeded: given rules, segments, and a context
/// (station, song index, time, minutes-since-start) it returns the segment to
/// inject (or null). The runtime performs the ducking/interruption; this only
/// decides. Song-based triggers are evaluated at song boundaries ([onSong]);
/// time-based triggers on a periodic tick ([onTick]).
class AutomationEngine {
  AutomationEngine({Random? rng}) : _rng = rng ?? Random();
  final Random _rng;

  bool _daypartOk(Daypart d, DateTime now) {
    switch (d) {
      case Daypart.any:
        return true;
      case Daypart.day:
        return now.hour >= 6 && now.hour < 18;
      case Daypart.night:
        return now.hour < 6 || now.hour >= 18;
    }
  }

  bool _stationOk(String ruleOrSegStation, DjStation station) =>
      ruleOrSegStation == 'all' || ruleOrSegStation == station.name;

  bool _songTrigger(RadioScheduleRule r, int songIndex) {
    switch (r.triggerType) {
      case TriggerType.afterSong:
      case TriggerType.beforeSong:
        return true;
      case TriggerType.everyXSongs:
        final n = r.triggerValue ?? 0;
        return n > 0 && songIndex > 0 && songIndex % n == 0;
      case TriggerType.randomRotation:
        return _rng.nextInt(4) == 0; // ~25% of song boundaries
      default:
        return false; // time-based (handled by onTick) or event triggers
    }
  }

  bool _timeTrigger(RadioScheduleRule r, DateTime now, int sessionMinutes) {
    switch (r.triggerType) {
      case TriggerType.everyXMinutes:
        final n = r.triggerValue ?? 0;
        return n > 0 && sessionMinutes > 0 && sessionMinutes % n == 0;
      case TriggerType.topOfHour:
        return now.minute == 0;
      case TriggerType.halfHour:
        return now.minute == 30;
      case TriggerType.quarterHour:
        return now.minute == 15 || now.minute == 45;
      case TriggerType.sunrise:
        return now.hour == 6 && now.minute == 0; // approximate
      case TriggerType.sunset:
        return now.hour == 18 && now.minute == 0; // approximate
      default:
        return false;
    }
  }

  /// Picks the highest-priority matching rule that has a playable segment.
  RadioSegment? _select(
    List<RadioScheduleRule> rules,
    List<RadioSegment> segments,
    DjStation station,
    DateTime now,
    bool Function(RadioScheduleRule) triggerMatch,
  ) {
    final matching = rules
        .where((r) =>
            r.enabled &&
            _stationOk(r.station, station) &&
            _daypartOk(r.daypart, now) &&
            triggerMatch(r))
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority)); // lower = higher
    for (final r in matching) {
      final cat = r.category == null ? null : SegmentCategory.fromDb(r.category);
      final pool = segments
          .where((s) =>
              s.published &&
              (cat == null || s.category == cat) &&
              _stationOk(s.station, station))
          .toList();
      if (pool.isNotEmpty) return pool[_rng.nextInt(pool.length)];
    }
    return null;
  }

  /// Song-boundary evaluation (after a track finishes).
  RadioSegment? onSong(
    List<RadioScheduleRule> rules,
    List<RadioSegment> segments, {
    required DjStation station,
    required int songIndex,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    return _select(rules, segments, station, t, (r) => _songTrigger(r, songIndex));
  }

  /// Timer evaluation (time-based triggers).
  RadioSegment? onTick(
    List<RadioScheduleRule> rules,
    List<RadioSegment> segments, {
    required DjStation station,
    required int sessionMinutes,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    return _select(
        rules, segments, station, t, (r) => _timeTrigger(r, t, sessionMinutes));
  }
}
