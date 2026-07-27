import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/narration/models/destination_narration.dart';
import 'package:explorer_os_mobile/features/narration/narration_qc.dart';

/// Aggregated narration coverage for a destination (studio header).
class NarrationCoverage {
  const NarrationCoverage({
    required this.scripts,
    required this.audioFiles,
    required this.approved,
    required this.published,
    required this.needsReview,
    required this.scriptTypes,
    this.lastGenerated,
    this.lastUpdated,
  });

  final int scripts;
  final int audioFiles;
  final int approved;
  final int published;
  final int needsReview;
  final int scriptTypes;
  final DateTime? lastGenerated;
  final DateTime? lastUpdated;

  /// 0..1 progress toward covering all 25 script types.
  double get progress =>
      (scriptTypes / NarrationScriptType.values.length).clamp(0, 1).toDouble();

  factory NarrationCoverage.fromList(List<DestinationNarration> list) {
    final types = <String>{};
    DateTime? lastGen, lastUpd;
    var audio = 0, approved = 0, published = 0, needs = 0;
    for (final n in list) {
      types.add(n.scriptType);
      if (n.hasAudio) audio++;
      if (n.status == NarrationStatus.approved) approved++;
      if (n.status == NarrationStatus.published) published++;
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
      approved: approved,
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
