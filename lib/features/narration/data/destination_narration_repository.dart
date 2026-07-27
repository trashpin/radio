import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/narration/models/destination_narration.dart';
import 'package:explorer_os_mobile/features/narration/narration_qc.dart';

/// Aggregated narration coverage for a destination (studio header).
class NarrationCoverage {
  const NarrationCoverage({
    required this.scripts,
    required this.audioFiles,
    required this.draft,
    required this.approved,
    required this.audioGenerated,
    required this.published,
    required this.needsReview,
    required this.scriptTypes,
    this.lastGenerated,
    this.lastUpdated,
  });

  final int scripts;
  final int audioFiles;
  final int draft;
  final int approved;
  final int audioGenerated;
  final int published;
  final int needsReview;
  final int scriptTypes;
  final DateTime? lastGenerated;
  final DateTime? lastUpdated;

  /// Script types with no narration yet (of the 25).
  int get missing => NarrationScriptType.values.length - scriptTypes;

  /// 0..1 progress toward covering all 25 script types.
  double get progress =>
      (scriptTypes / NarrationScriptType.values.length).clamp(0, 1).toDouble();

  factory NarrationCoverage.fromList(List<DestinationNarration> list) {
    final types = <String>{};
    DateTime? lastGen, lastUpd;
    var audio = 0, draft = 0, approved = 0, audioGen = 0, published = 0, needs = 0;
    for (final n in list) {
      types.add(n.scriptType);
      if (n.hasAudio) audio++;
      switch (n.status) {
        case NarrationStatus.draft:
          draft++;
        case NarrationStatus.approved:
          approved++;
        case NarrationStatus.audioGenerated:
          audioGen++;
        case NarrationStatus.published:
          published++;
        case NarrationStatus.needsReview:
        case NarrationStatus.archived:
          break;
      }
      if (n.needsReview) needs++;
      if (n.createdAt != null &&
          (lastGen == null || n.createdAt!.isAfter(lastGen))) {
        lastGen = n.createdAt;
      }
      if (n.updatedAt != null &&
          (lastUpd == null || n.updatedAt!.isAfter(lastUpd))) {
        lastUpd = n.updatedAt;
      }
    }
    return NarrationCoverage(
      scripts: list.length,
      audioFiles: audio,
      draft: draft,
      approved: approved,
      audioGenerated: audioGen,
      published: published,
      needsReview: needs,
      scriptTypes: types.length,
      lastGenerated: lastGen,
      lastUpdated: lastUpd,
    );
  }
}

/// The scope a bulk narration job covers.
enum NarrationScope {
  destination('destination', 'This Destination'),
  park('park', 'Entire Park'),
  county('county', 'Entire County'),
  state('state', 'Entire State'),
  category('category', 'Entire Category'),
  country('country', 'Entire Country');

  const NarrationScope(this.dbValue, this.label);
  final String dbValue;
  final String label;
}

/// Data access for the AI Narration Studio.
class DestinationNarrationRepository {
  const DestinationNarrationRepository();

  Future<List<DestinationNarration>> forDestination(String destinationId) async {
    if (!SupabaseService.isConfigured || destinationId.isEmpty) return const [];
    try {
      final rows = await SupabaseService.client
          .from('destination_narrations')
          .select()
          .eq('destination_id', destinationId)
          .order('script_type')
          .order('variant') as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(DestinationNarration.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> setStatus(String id, NarrationStatus status) =>
      SupabaseService.client.from('destination_narrations').update({
        'status': status.dbValue,
        if (status == NarrationStatus.approved) 'approved_at': _now(),
      }).eq('id', id);

  Future<void> approve(String id) => setStatus(id, NarrationStatus.approved);

  /// Reject an approved/draft script back to draft for another edit pass.
  Future<void> reject(String id) => setStatus(id, NarrationStatus.draft);

  /// Publish (explicit admin action). Only meaningful once audio exists.
  Future<void> publish(String id) => setStatus(id, NarrationStatus.published);

  Future<void> archive(String id) => setStatus(id, NarrationStatus.archived);

  /// Duplicate a script as a fresh draft (no audio, awaiting review).
  Future<void> duplicate(DestinationNarration n) =>
      SupabaseService.client.from('destination_narrations').insert({
        'destination_id': n.destinationId,
        'script_type': n.scriptType,
        'title': '${n.title ?? n.scriptType} (copy)',
        'script': n.script,
        'variant': n.variant,
        'language': n.language,
        'word_count': n.wordCount,
        'speaking_seconds': n.speakingSeconds,
        'status': NarrationStatus.draft.dbValue,
      });

  /// Enqueue a bulk audio job over a scope (processed by the audio worker,
  /// which voices approved scripts that lack audio). Never publishes.
  Future<void> enqueueBulkAudio({
    required String destinationName,
    String? category,
    String? state,
    String? county,
    NarrationScope scope = NarrationScope.destination,
  }) async {
    if (!SupabaseService.isConfigured) return;
    await SupabaseService.client.from('generation_jobs').insert({
      'destination': destinationName,
      'job_type': 'narration_audio',
      'status': 'pending',
      'destination_category': ?category,
      'state': ?state,
      'county': ?county,
      'notes': 'narration_audio|scope=${scope.dbValue}',
    });
  }

  /// Save an edited script; recomputes word count + speaking time.
  Future<void> updateScript(String id, {String? title, required String script}) {
    final words = wordCount(script);
    return SupabaseService.client.from('destination_narrations').update({
      'title': ?title,
      'script': script,
      'word_count': words,
      'speaking_seconds': speakingSeconds(words),
      'readability_score': readabilityScore(script),
    }).eq('id', id);
  }

  Future<void> deleteNarration(String id) =>
      SupabaseService.client.from('destination_narrations').delete().eq('id', id);

  /// Enqueue a generation job (processed by tool/generate_narration.dart).
  /// [mode] is 'all' | 'missing' | a specific script_type dbValue.
  Future<void> enqueueGenerate({
    required String destinationName,
    String? category,
    String? state,
    String? county,
    NarrationScope scope = NarrationScope.destination,
    String mode = 'all',
  }) async {
    if (!SupabaseService.isConfigured) return;
    await SupabaseService.client.from('generation_jobs').insert({
      'destination': destinationName,
      'job_type': 'narration',
      'status': 'pending',
      'destination_category': ?category,
      'state': ?state,
      'county': ?county,
      'notes': 'narration|scope=${scope.dbValue}|mode=$mode',
    });
  }

  /// Enqueue an audio-generation job for one narration script.
  Future<void> enqueueAudio(DestinationNarration n, {String? voice}) async {
    if (!SupabaseService.isConfigured) return;
    await SupabaseService.client.from('generation_jobs').insert({
      'destination': n.destinationId,
      'job_type': 'narration_audio',
      'status': 'pending',
      'notes': 'narration_audio|id=${n.id}${voice != null ? '|voice=$voice' : ''}',
    });
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();
}

final destinationNarrationRepositoryProvider =
    Provider<DestinationNarrationRepository>(
        (ref) => const DestinationNarrationRepository());

/// Bumped after any narration write to refetch the studio.
class NarrationRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final narrationRefreshProvider =
    NotifierProvider<NarrationRefresh, int>(NarrationRefresh.new);

final destinationNarrationsProvider =
    FutureProvider.family<List<DestinationNarration>, String>((ref, destId) {
  ref.watch(narrationRefreshProvider);
  return ref.watch(destinationNarrationRepositoryProvider).forDestination(destId);
});
