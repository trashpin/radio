import 'package:flutter/material.dart';

/// The kinds of content a rundown item can be. The value order is the Content
/// Library order. Each carries a default duration + how it plays (recorded
/// audio, spoken text via TTS, or a timed gap).
enum RundownItemType {
  music('music', 'Music', Icons.music_note_rounded, 180),
  djBanter('dj_banter', 'DJ Banter', Icons.mic_rounded, 20),
  stationId('station_id', 'Station ID', Icons.radio_rounded, 8),
  sweeper('sweeper', 'Sweeper', Icons.graphic_eq_rounded, 5),
  localFact('local_fact', 'Local Fact', Icons.lightbulb_rounded, 20),
  history('history', 'History', Icons.history_edu_rounded, 60),
  weather('weather', 'Weather', Icons.cloud_rounded, 25),
  event('event', 'Event', Icons.event_rounded, 30),
  locationStory('location_story', 'Location Story', Icons.place_rounded, 90),
  customAudio('custom_audio', 'Custom Audio', Icons.audiotrack_rounded, 60),
  silence('silence', 'Silence', Icons.hourglass_empty_rounded, 5);

  const RundownItemType(this.id, this.label, this.icon, this.defaultSeconds);
  final String id;
  final String label;
  final IconData icon;
  final int defaultSeconds;

  /// Pure timed gap — nothing to play, just wait.
  bool get isSilence => this == RundownItemType.silence;

  /// Types that are fundamentally recorded audio (need an audio URL to play).
  bool get isAudioFirst =>
      this == RundownItemType.music ||
      this == RundownItemType.customAudio ||
      this == RundownItemType.sweeper ||
      this == RundownItemType.stationId;

  static RundownItemType fromId(String? id) => RundownItemType.values.firstWhere(
        (t) => t.id == id,
        orElse: () => RundownItemType.customAudio,
      );
}

/// How often a rundown repeats.
enum RundownRecurrence {
  none('none', 'One-time'),
  daily('daily', 'Daily'),
  weekdays('weekdays', 'Weekdays'),
  weekly('weekly', 'Weekly'),
  monthly('monthly', 'Monthly');

  const RundownRecurrence(this.id, this.label);
  final String id;
  final String label;

  static RundownRecurrence fromId(String? id) =>
      RundownRecurrence.values.firstWhere((r) => r.id == id,
          orElse: () => RundownRecurrence.none);
}

/// One line in a rundown timeline.
class RundownItem {
  const RundownItem({
    required this.id,
    required this.rundownId,
    required this.type,
    required this.sortOrder,
    this.name = '',
    this.durationSeconds = 0,
    this.enabled = true,
    this.audioUrl,
    this.script,
    this.refId,
  });

  final String id;
  final String rundownId;
  final RundownItemType type;
  final int sortOrder;
  final String name;
  final int durationSeconds;
  final bool enabled;

  /// Recorded audio to play (music/custom/sweeper/station ID, or a voiced clip).
  final String? audioUrl;

  /// Spoken text (fact/history/weather/story/banter) — TTS when there's no audio.
  final String? script;

  /// Optional reference into another table (a location id, an event id, …).
  final String? refId;

  String get displayName => name.trim().isNotEmpty ? name : type.label;
  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
  bool get hasScript => (script ?? '').trim().isNotEmpty;

  /// Effective duration (falls back to the type's default when unset).
  int get effectiveSeconds =>
      durationSeconds > 0 ? durationSeconds : type.defaultSeconds;

  /// Whether this item can actually be played right now. Silence is always
  /// playable (a timed gap); everything else needs audio or a script.
  bool get isPlayable => type.isSilence || hasAudio || hasScript;

  RundownItem copyWith({
    String? rundownId,
    int? sortOrder,
    String? name,
    int? durationSeconds,
    bool? enabled,
    String? audioUrl,
    String? script,
    String? refId,
    RundownItemType? type,
  }) =>
      RundownItem(
        id: id,
        rundownId: rundownId ?? this.rundownId,
        type: type ?? this.type,
        sortOrder: sortOrder ?? this.sortOrder,
        name: name ?? this.name,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        enabled: enabled ?? this.enabled,
        audioUrl: audioUrl ?? this.audioUrl,
        script: script ?? this.script,
        refId: refId ?? this.refId,
      );

  factory RundownItem.fromJson(Map<String, dynamic> j) => RundownItem(
        id: (j['id'] ?? '').toString(),
        rundownId: (j['rundown_id'] ?? '').toString(),
        type: RundownItemType.fromId(j['type'] as String?),
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '') as String,
        durationSeconds: (j['duration_seconds'] as num?)?.toInt() ?? 0,
        enabled: (j['enabled'] ?? true) as bool,
        audioUrl: j['audio_url'] as String?,
        script: j['script'] as String?,
        refId: j['ref_id']?.toString(),
      );

  Map<String, dynamic> toWrite() => {
        'rundown_id': rundownId,
        'type': type.id,
        'sort_order': sortOrder,
        'name': name,
        'duration_seconds': durationSeconds,
        'enabled': enabled,
        'audio_url': audioUrl,
        'script': script,
        'ref_id': refId,
      };
}

/// A named, schedulable radio rundown (a "clock"/log of items to air in order).
class Rundown {
  const Rundown({
    required this.id,
    required this.name,
    this.scheduledAt,
    this.recurrence = RundownRecurrence.none,
    this.published = false,
    this.active = true,
    this.createdAt,
    this.items = const [],
  });

  final String id;
  final String name;
  final DateTime? scheduledAt;
  final RundownRecurrence recurrence;
  final bool published;
  final bool active;
  final DateTime? createdAt;

  /// Items in air order (sorted by [RundownItem.sortOrder] by the repository).
  final List<RundownItem> items;

  List<RundownItem> get enabledItems =>
      [for (final i in items) if (i.enabled) i];

  /// Total runtime of the enabled items, in seconds.
  int get totalSeconds =>
      enabledItems.fold(0, (sum, i) => sum + i.effectiveSeconds);

  Rundown copyWith({
    String? name,
    DateTime? scheduledAt,
    RundownRecurrence? recurrence,
    bool? published,
    bool? active,
    List<RundownItem>? items,
  }) =>
      Rundown(
        id: id,
        name: name ?? this.name,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        recurrence: recurrence ?? this.recurrence,
        published: published ?? this.published,
        active: active ?? this.active,
        createdAt: createdAt,
        items: items ?? this.items,
      );

  factory Rundown.fromJson(Map<String, dynamic> j) => Rundown(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Untitled rundown') as String,
        scheduledAt:
            DateTime.tryParse((j['scheduled_at'] ?? '') as String? ?? ''),
        recurrence: RundownRecurrence.fromId(j['recurrence'] as String?),
        published: (j['published'] ?? false) as bool,
        active: (j['active'] ?? true) as bool,
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String? ?? ''),
      );

  Map<String, dynamic> toWrite() => {
        'name': name,
        'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'recurrence': recurrence.id,
        'published': published,
        'active': active,
      };
}

/// A computed timeline row: an item plus its clock start/end. Pure output of
/// [computeRundownTimeline].
class RundownSlot {
  const RundownSlot({
    required this.item,
    required this.startOffset,
    required this.endOffset,
    this.startClock,
    this.endClock,
  });

  final RundownItem item;

  /// Seconds from the rundown start.
  final int startOffset;
  final int endOffset;

  /// Absolute wall-clock times when a start time is known.
  final DateTime? startClock;
  final DateTime? endClock;

  int get seconds => endOffset - startOffset;
}

/// Lays out the ENABLED items back-to-back from [start], computing each item's
/// offset + clock times. Pure + deterministic — the timeline UI and the
/// player both read from this so "what airs when" is defined once.
List<RundownSlot> computeRundownTimeline(
  List<RundownItem> items, {
  DateTime? start,
}) {
  final out = <RundownSlot>[];
  var offset = 0;
  for (final item in items) {
    if (!item.enabled) continue;
    final secs = item.effectiveSeconds;
    out.add(RundownSlot(
      item: item,
      startOffset: offset,
      endOffset: offset + secs,
      startClock: start?.add(Duration(seconds: offset)),
      endClock: start?.add(Duration(seconds: offset + secs)),
    ));
    offset += secs;
  }
  return out;
}

/// mm:ss for a duration in seconds (timeline + now-playing displays).
String formatClockSeconds(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}
