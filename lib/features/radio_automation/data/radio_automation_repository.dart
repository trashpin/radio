import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/dj/models/dj_clip.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_schedule_rule.dart';
import 'package:explorer_os_mobile/features/radio_automation/models/radio_segment.dart';

/// Data access for the Radio Automation library + scheduling rules.
class RadioAutomationRepository {
  const RadioAutomationRepository();

  // ── Segments ──
  Future<List<RadioSegment>> segments() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('radio_segments')
          .select()
          .order('created_at', ascending: false) as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(RadioSegment.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> insertSegment(RadioSegment s) =>
      SupabaseService.client.from('radio_segments').insert(s.toInsert());

  Future<void> setPublished(String id, bool published) => SupabaseService.client
      .from('radio_segments')
      .update({'published': published, 'updated_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', id);

  Future<void> deleteSegment(String id) =>
      SupabaseService.client.from('radio_segments').delete().eq('id', id);

  Future<void> duplicateSegment(RadioSegment s) => SupabaseService.client
      .from('radio_segments')
      .insert({...s.toInsert(), 'title': '${s.title} (copy)', 'published': false});

  // ── Rules ──
  Future<List<RadioScheduleRule>> rules() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('radio_schedule_rules')
          .select()
          .order('priority') as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(RadioScheduleRule.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> insertRule(RadioScheduleRule r) =>
      SupabaseService.client.from('radio_schedule_rules').insert(r.toInsert());

  Future<void> setRuleEnabled(String id, bool enabled) => SupabaseService.client
      .from('radio_schedule_rules')
      .update({'enabled': enabled}).eq('id', id);

  Future<void> deleteRule(String id) =>
      SupabaseService.client.from('radio_schedule_rules').delete().eq('id', id);

  /// Published segments that have audio, mapped to [DjClip]s the runtime can
  /// play between songs (in the segment's voice).
  Future<List<DjClip>> playableClips() async {
    final all = await segments();
    final clips = <DjClip>[];
    for (final s in all) {
      if (!s.published || !s.hasAudio) continue;
      final situation = _situationFor(s.category);
      if (situation == null) continue;
      clips.add(DjClip(
        id: 'seg:${s.id}',
        station: DjStation.values
            .firstWhere((e) => e.name == s.station, orElse: () => DjStation.all),
        situation: situation,
        audioUrl: s.audioUrl!,
        voiceName: s.voice,
        voiceId: s.voiceId,
        text: s.script,
      ));
    }
    return clips;
  }

  static BanterSituation? _situationFor(SegmentCategory c) {
    switch (c) {
      case SegmentCategory.djBanter:
      case SegmentCategory.songOutro:
        return BanterSituation.songOutro;
      case SegmentCategory.songIntro:
        return BanterSituation.songIntro;
      case SegmentCategory.stationId:
      case SegmentCategory.promo:
        return BanterSituation.stationId;
      case SegmentCategory.wildlifeIntro:
        return BanterSituation.wildlifeSighting;
      case SegmentCategory.weather:
        return BanterSituation.weather;
      case SegmentCategory.safety:
        return BanterSituation.safetyReminder;
      case SegmentCategory.gpsTransition:
        return BanterSituation.gpsApproaching;
      case SegmentCategory.story:
        return null; // stories aren't DJ banter — not played via the clip path
    }
  }
}

final radioAutomationRepositoryProvider =
    Provider<RadioAutomationRepository>((ref) => const RadioAutomationRepository());

/// All segments (refreshable via [segmentsRefreshProvider]).
final radioSegmentsProvider = FutureProvider<List<RadioSegment>>((ref) {
  ref.watch(segmentsRefreshProvider);
  return ref.watch(radioAutomationRepositoryProvider).segments();
});

final radioRulesProvider = FutureProvider<List<RadioScheduleRule>>((ref) {
  ref.watch(segmentsRefreshProvider);
  return ref.watch(radioAutomationRepositoryProvider).rules();
});

/// Bump to reload the library/rules after a change.
class SegmentsRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final segmentsRefreshProvider =
    NotifierProvider<SegmentsRefresh, int>(SegmentsRefresh.new);
