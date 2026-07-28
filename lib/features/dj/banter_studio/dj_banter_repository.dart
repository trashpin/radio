import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/content_generator/models/content_models.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/banter_category.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/banter_templates.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/dj_banter_clip.dart';

/// Target number of clips per category, per destination (brief: 20–50).
const int kBanterTargetPerCategory = 20;

/// Data access + orchestration for the DJ Banter Studio (`dj_banter` +
/// `dj_banter_versions`). Read-safe when Supabase isn't configured.
class DjBanterRepository {
  const DjBanterRepository();

  Future<List<DjBanterClip>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('dj_banter')
          .select()
          .order('created_at', ascending: false) as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(DjBanterClip.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Published, playable clips for the runtime director (optionally scoped to a
  /// destination code).
  Future<List<DjBanterClip>> publishedFor({String? destinationCode}) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      var query = SupabaseService.client
          .from('dj_banter')
          .select()
          .eq('status', BanterStatus.published.id);
      if (destinationCode != null && destinationCode.isNotEmpty) {
        query = query.eq('destination_code', destinationCode);
      }
      final rows = await query as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(DjBanterClip.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> insertMany(List<DjBanterClip> clips) async {
    if (clips.isEmpty) return;
    final payload = clips.map((c) => c.toWrite()).toList();
    await SupabaseService.client.from('dj_banter').insert(payload);
  }

  /// Generates [count] draft clips for a category from the seed templates.
  Future<int> generate(
    BanterCategory category, {
    required int count,
    String? destinationCode,
    String? destinationId,
    String? gpsRegion,
    String? guideMode,
    String? voiceId,
    String? voiceName,
  }) async {
    final drafts = buildBanterDrafts(
      category,
      count: count,
      destinationCode: destinationCode,
      destinationId: destinationId,
      gpsRegion: gpsRegion,
      guideMode: guideMode,
      voiceId: voiceId,
      voiceName: voiceName,
    );
    await insertMany(drafts);
    return drafts.length;
  }

  /// Fills every category for a destination up to [target], generating only the
  /// missing clips ("Bulk Generate Missing").
  Future<int> generateMissing({
    required String destinationCode,
    String? destinationId,
    String? gpsRegion,
    int target = kBanterTargetPerCategory,
  }) async {
    final existing = await all();
    final counts = <BanterCategory, int>{};
    for (final c in existing) {
      if (c.destinationCode == destinationCode) {
        counts[c.category] = (counts[c.category] ?? 0) + 1;
      }
    }
    var generated = 0;
    for (final category in BanterCategory.values) {
      final have = counts[category] ?? 0;
      final need = target - have;
      if (need <= 0) continue;
      generated += await generate(
        category,
        count: need,
        destinationCode: destinationCode,
        destinationId: destinationId,
        gpsRegion: gpsRegion,
      );
    }
    return generated;
  }

  /// Edits a clip's text, snapshotting the previous version to history first.
  Future<void> saveEdit(
    DjBanterClip clip,
    String newText, {
    String? author,
  }) async {
    await _snapshot(clip, author: author);
    await SupabaseService.client.from('dj_banter').update({
      'text': newText,
      'version': clip.version + 1,
    }).eq('id', clip.id);
  }

  Future<void> setStatus(String id, BanterStatus status) => SupabaseService
      .client
      .from('dj_banter')
      .update({'status': status.id}).eq('id', id);

  Future<void> setVoice(String id, String voiceId, String voiceName) =>
      SupabaseService.client.from('dj_banter').update({
        'voice_id': voiceId,
        'voice_name': voiceName,
      }).eq('id', id);

  Future<void> assignDestination(String id, String? destinationCode) =>
      SupabaseService.client
          .from('dj_banter')
          .update({'destination_code': destinationCode}).eq('id', id);

  Future<void> assignRegion(String id, String? gpsRegion) => SupabaseService
      .client
      .from('dj_banter')
      .update({'gps_region': gpsRegion}).eq('id', id);

  Future<void> delete(String id) =>
      SupabaseService.client.from('dj_banter').delete().eq('id', id);

  Future<List<DjBanterVersion>> versions(String banterId) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('dj_banter_versions')
          .select()
          .eq('banter_id', banterId)
          .order('version', ascending: false) as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(DjBanterVersion.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Records a play through the DB RPC (bumps counters + last_played).
  Future<void> recordPlay(String id) async {
    if (!SupabaseService.isConfigured) return;
    try {
      await SupabaseService.client
          .rpc('dj_banter_record_play', params: {'p_id': id});
    } catch (_) {}
  }

  /// Enqueues a voicing job so the ElevenLabs tool/worker generates audio for a
  /// destination's banter (consistent with the Audio Production queue).
  Future<void> enqueueVoiceJob({
    required String destinationCode,
    String? name,
  }) {
    final job = GenerationJob(
      id: '',
      destination: name ?? destinationCode,
      jobType: JobType.audio,
      status: JobStatus.pending,
      notes: 'dj_banter:voice;code=$destinationCode',
    );
    return SupabaseService.client
        .from('generation_jobs')
        .insert(job.toInsert());
  }

  Future<void> _snapshot(DjBanterClip clip, {String? author}) async {
    try {
      await SupabaseService.client.from('dj_banter_versions').insert({
        'banter_id': clip.id,
        'version': clip.version,
        'text': clip.text,
        'voice_id': clip.voiceId,
        'voice_name': clip.voiceName,
        'author': author,
      });
    } catch (_) {
      // Version history requires migration 0028; ignore if not yet applied.
    }
  }
}

final djBanterRepositoryProvider =
    Provider<DjBanterRepository>((ref) => const DjBanterRepository());

/// Bump to refetch after a write.
class DjBanterRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final djBanterRefreshProvider =
    NotifierProvider<DjBanterRefresh, int>(DjBanterRefresh.new);

final djBanterAllProvider = FutureProvider<List<DjBanterClip>>((ref) {
  ref.watch(djBanterRefreshProvider);
  return ref.watch(djBanterRepositoryProvider).all();
});

/// Per-(destination, category) coverage counts for the studio dashboard.
class BanterCoverage {
  const BanterCoverage(this.byCategory, this.total);
  final Map<BanterCategory, int> byCategory;
  final int total;

  int get missingCategories =>
      BanterCategory.values.where((c) => (byCategory[c] ?? 0) == 0).length;
}

BanterCoverage computeCoverage(
  List<DjBanterClip> clips, {
  String? destinationCode,
}) {
  final counts = <BanterCategory, int>{};
  var total = 0;
  for (final c in clips) {
    if (destinationCode != null && c.destinationCode != destinationCode) {
      continue;
    }
    counts[c.category] = (counts[c.category] ?? 0) + 1;
    total++;
  }
  return BanterCoverage(counts, total);
}
