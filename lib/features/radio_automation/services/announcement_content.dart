import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/radio_automation/data/radio_automation_repository.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_schedule_rule.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_segment.dart';

/// Scheduler Reconciliation — Step 1 (additive; NOT wired into playback yet).
///
/// A single pool of every non-music announcement the automation layer could
/// play, expressed in the ONE [RadioSegment] shape [AutomationEngine] already
/// selects from. It unifies:
///   • the automation library (`radio_segments`), and
///   • the legacy domain tables `RadioScheduler` reads directly
///     (`safety_messages`, `wildlife_alerts`, published `stories`).
///
/// This lets a future step drive all announcements through ONE engine instead
/// of two. Nothing consumes this provider yet, so behavior is unchanged;
/// `RadioScheduler` keeps running exactly as before.
///
/// The adapters are pure (row map → [RadioSegment]) so they're unit-testable
/// without a network; only [unifiedAnnouncementContentProvider] does I/O.

/// Adapts a `safety_messages` row into a [SegmentCategory.safety] segment.
RadioSegment? safetyMessageToSegment(Map<String, dynamic> row) =>
    _fromDomainRow(row, SegmentCategory.safety, 'safety', 'Safety message');

/// Adapts a `wildlife_alerts` row into a [SegmentCategory.wildlifeIntro] segment.
RadioSegment? wildlifeAlertToSegment(Map<String, dynamic> row) =>
    _fromDomainRow(row, SegmentCategory.wildlifeIntro, 'wildlife',
        'Wildlife update');

/// Adapts a published `stories` row into a [SegmentCategory.story] segment.
RadioSegment? storyToSegment(Map<String, dynamic> row) {
  final id = (row['story_id'] ?? row['id'] ?? '').toString();
  return _segment(id, 'story', SegmentCategory.story, row,
      fallbackTitle: 'Story');
}

RadioSegment? _fromDomainRow(
  Map<String, dynamic> row,
  SegmentCategory category,
  String prefix,
  String fallbackTitle,
) =>
    _segment((row['id'] ?? '').toString(), prefix, category, row,
        fallbackTitle: fallbackTitle);

RadioSegment? _segment(
  String rawId,
  String prefix,
  SegmentCategory category,
  Map<String, dynamic> row, {
  required String fallbackTitle,
}) {
  final audio = (row['audio_url'] as String?)?.trim();
  if (rawId.isEmpty || audio == null || audio.isEmpty) return null; // playable only
  return RadioSegment(
    id: '$prefix:$rawId',
    title: (row['title'] as String?)?.trim().isNotEmpty == true
        ? row['title'] as String
        : fallbackTitle,
    category: category,
    station: 'all', // domain announcements aren't station-specific
    script: row['script'] as String? ?? row['body'] as String?,
    audioUrl: audio,
    generatedByAi: false,
    published: true, // already filtered to active/published + has audio
  );
}

/// Combines the automation library with the adapted legacy sources into one
/// pool. Pure — the caller supplies already-fetched rows. Rows without playable
/// audio are dropped by the adapters.
List<RadioSegment> combineAnnouncementContent({
  List<RadioSegment> segments = const [],
  List<Map<String, dynamic>> safety = const [],
  List<Map<String, dynamic>> wildlife = const [],
  List<Map<String, dynamic>> stories = const [],
}) =>
    [
      ...segments,
      for (final r in safety) ?safetyMessageToSegment(r),
      for (final r in wildlife) ?wildlifeAlertToSegment(r),
      for (final r in stories) ?storyToSegment(r),
    ];

/// Adapts a legacy `radio_schedule` row (the table `RadioScheduler` reads) into
/// an [AutomationEngine] rule, so the single automation engine can honor the
/// existing interval announcement rules. Returns null for rows the legacy
/// scheduler itself never fired: non-`interval` cadences (its `_tick` only ran
/// interval rules) or unknown content types.
RadioScheduleRule? legacyScheduleRuleToRule(Map<String, dynamic> row) {
  final cadence = (row['cadence'] ?? 'interval') as String;
  if (cadence != 'interval') return null;
  final category = switch ((row['content_type'] ?? 'safety') as String) {
    'safety' => SegmentCategory.safety,
    'wildlife' => SegmentCategory.wildlifeIntro,
    'story' => SegmentCategory.story,
    'station_id' => SegmentCategory.stationId,
    _ => null,
  };
  if (category == null) return null;
  final id = (row['id'] ?? '').toString();
  if (id.isEmpty) return null;
  final mins = (row['interval_minutes'] as num?)?.toInt() ?? 15;
  final legacyPriority = (row['priority'] as num?)?.toInt() ?? 5;
  return RadioScheduleRule(
    id: 'legacy:$id',
    name: (row['name'] as String?) ?? '${category.label} (legacy schedule)',
    station: 'all',
    triggerType: TriggerType.everyXMinutes,
    triggerValue: mins <= 0 ? 15 : mins,
    category: category.dbValue,
    // Legacy uses higher number = higher priority; automation is the inverse
    // (lower = higher), so invert to preserve relative ordering.
    priority: (100 - legacyPriority).clamp(0, 100),
    enabled: (row['active'] ?? true) as bool,
  );
}

/// The unified automation rule set: the modern `radio_schedule_rules` plus the
/// legacy `radio_schedule` interval rules adapted into the same shape — so ONE
/// engine ([AutomationEngine]) evaluates every announcement rule.
final unifiedAutomationRulesProvider =
    FutureProvider<List<RadioScheduleRule>>((ref) async {
  final rules = await ref.watch(radioAutomationRepositoryProvider).rules();
  if (!SupabaseService.isConfigured) return rules;
  var legacy = const <Map<String, dynamic>>[];
  try {
    final rows = await SupabaseService.client
        .from('radio_schedule')
        .select()
        .eq('active', true) as List;
    legacy = rows.cast<Map<String, dynamic>>();
  } catch (_) {}
  return [
    ...rules,
    for (final r in legacy) ?legacyScheduleRuleToRule(r),
  ];
});

/// The unified announcement pool (automation segments + safety/wildlife/story).
/// Loads defensively — missing tables / unconfigured Supabase just contribute
/// nothing. NOT consumed by the runtime yet (Step 1 is additive).
final unifiedAnnouncementContentProvider =
    FutureProvider<List<RadioSegment>>((ref) async {
  final segments =
      await ref.watch(radioAutomationRepositoryProvider).segments();
  if (!SupabaseService.isConfigured) return segments;

  Future<List<Map<String, dynamic>>> load(
    String table, {
    String activeFlag = 'active',
  }) async {
    try {
      final rows = await SupabaseService.client
          .from(table)
          .select()
          .eq(activeFlag, true)
          .not('audio_url', 'is', null) as List;
      return rows.cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  final safety = await load('safety_messages');
  final wildlife = await load('wildlife_alerts');
  final stories = await load('stories', activeFlag: 'published');

  return combineAnnouncementContent(
    segments: segments,
    safety: safety,
    wildlife: wildlife,
    stories: stories,
  );
});
