/// When a scheduled segment should play. Covers the full professional trigger
/// set; `needsValue` marks the "every N" triggers that read [trigger_value].
enum TriggerType {
  beforeSong('BEFORE_SONG', 'Before Song'),
  afterSong('AFTER_SONG', 'After Song'),
  everyXSongs('EVERY_X_SONGS', 'Every X Songs', needsValue: true),
  everyXMinutes('EVERY_X_MINUTES', 'Every X Minutes', needsValue: true),
  topOfHour('TOP_OF_HOUR', 'Top of Hour'),
  halfHour('HALF_HOUR', 'Half Hour'),
  quarterHour('QUARTER_HOUR', 'Quarter Hour'),
  stationStart('STATION_START', 'Station Start'),
  stationEnd('STATION_END', 'Station End'),
  gpsArrival('GPS_ARRIVAL', 'GPS Arrival'),
  enteringRegion('ENTERING_REGION', 'Entering New Region'),
  sunrise('SUNRISE', 'Sunrise'),
  sunset('SUNSET', 'Sunset'),
  weatherAlert('WEATHER_ALERT', 'Weather Alert'),
  randomRotation('RANDOM_ROTATION', 'Random Rotation'),
  manual('MANUAL', 'Manual Trigger');

  const TriggerType(this.dbValue, this.label, {this.needsValue = false});
  final String dbValue;
  final String label;
  final bool needsValue;

  static TriggerType fromDb(String? v) => TriggerType.values.firstWhere(
        (e) => e.dbValue == v,
        orElse: () => TriggerType.everyXSongs,
      );
}

/// Which part of the day a rule is active.
enum Daypart {
  any('any', 'Any time'),
  day('day', 'Daytime only'),
  night('night', 'Nighttime only');

  const Daypart(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static Daypart fromDb(String? v) =>
      Daypart.values.firstWhere((e) => e.dbValue == v, orElse: () => Daypart.any);
}

/// A scheduling rule (mirrors `radio_schedule_rules`).
class RadioScheduleRule {
  const RadioScheduleRule({
    required this.id,
    required this.name,
    required this.station,
    required this.triggerType,
    this.parkId,
    this.category,
    this.triggerValue,
    this.daypart = Daypart.any,
    this.priority = 5,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String station;
  final TriggerType triggerType;
  final String? parkId;
  final String? category; // SegmentCategory.dbValue this rule plays
  final int? triggerValue;
  final Daypart daypart;
  final int priority;
  final bool enabled;

  factory RadioScheduleRule.fromJson(Map<String, dynamic> j) => RadioScheduleRule(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Rule') as String,
        station: (j['station'] ?? 'all') as String,
        triggerType: TriggerType.fromDb(j['trigger_type'] as String?),
        parkId: j['park_id'] as String?,
        category: j['category'] as String?,
        triggerValue: (j['trigger_value'] as num?)?.toInt(),
        daypart: Daypart.fromDb(j['daypart'] as String?),
        priority: (j['priority'] as num?)?.toInt() ?? 5,
        enabled: (j['enabled'] ?? true) as bool,
      );

  Map<String, dynamic> toInsert() => {
        'name': name,
        'station': station,
        'trigger_type': triggerType.dbValue,
        if (parkId != null) 'park_id': parkId,
        if (category != null) 'category': category,
        if (triggerValue != null) 'trigger_value': triggerValue,
        'daypart': daypart.dbValue,
        'priority': priority,
        'enabled': enabled,
      };
}
