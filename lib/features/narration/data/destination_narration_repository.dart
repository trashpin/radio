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

  /// The best published narration for "Tell Me More": the first
  /// [scriptTypes] (in preference order) that has a published row, picking
  /// randomly among that type's variants so repeat taps don't always surface
  /// the same script.
  Future<DestinationNarration?> bestPublishedFor({
    required String destinationId,
    required List<String> scriptTypes,
  }) async {
    if (!SupabaseService.isConfigured ||
        destinationId.isEmpty ||
        scriptTypes.isEmpty) {
      return null;
    }
    try {
      final rows = await SupabaseService.client
          .from('destination_narrations')
          .select()
          .eq('destination_id', destinationId)
          .eq('status', NarrationStatus.published.dbValue)
          .inFilter('script_type', scriptTypes) as List;
      final narrations = rows
          .cast<Map<String, dynamic>>()
          .map(DestinationNarration.fromJson)
          .toList();
      if (narrations.isEmpty) return null;
      for (final type in scriptTypes) {
        final matches =
            narrations.where((n) => n.scriptType == type).toList();
        if (matches.isNotEmpty) {
          matches.shuffle();
          return matches.first;
        }
      }
      return null;
    } catch (_) {
      return null;
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

  /// Set the voice for a single narration (persists voice_id + name).
  Future<void> setVoice(String id, String voiceId, String voiceName) =>
      SupabaseService.client
          .from('destination_narrations')
          .update({'voice_id': voiceId, 'voice': voiceName}).eq('id', id);

  Future<void> clearVoice(String id) => SupabaseService.client
      .from('destination_narrations')
      .update({'voice_id': null, 'voice': null}).eq('id', id);

  /// Change voice and regenerate audio WITHOUT touching the script: sets the
  /// voice, clears the old audio, moves back to approved, and queues an audio
  /// job (the worker voices it with the selected voice).
  Future<void> regenerateAudio(DestinationNarration n,
      {String? voiceId, String? voiceName}) async {
    final patch = <String, dynamic>{
      'audio_url': null,
      'audio_generated_at': null,
      'status': NarrationStatus.approved.dbValue,
    };
    if (voiceId != null) {
      patch['voice_id'] = voiceId;
      patch['voice'] = voiceName;
    }
    await SupabaseService.client
        .from('destination_narrations')
        .update(patch)
        .eq('id', n.id);
    await enqueueAudio(n, voice: voiceName);
  }

  /// Per-destination default voice (voice_defaults scope=destination).
  Future<String?> destinationDefaultVoiceId(String destId) async {
    if (!SupabaseService.isConfigured || destId.isEmpty) return null;
    try {
      final rows = await SupabaseService.client
          .from('voice_defaults')
          .select('voice_id')
          .eq('scope', 'destination')
          .eq('scope_value', destId)
          .limit(1) as List;
      return rows.isEmpty ? null : rows.first['voice_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> setDestinationDefaultVoice(
          String destId, String voiceId, String voiceName) =>
      SupabaseService.client.from('voice_defaults').upsert({
        'scope': 'destination',
        'scope_value': destId,
        'voice_id': voiceId,
        'voice_name': voiceName,
      }, onConflict: 'scope,scope_value');

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

/// The per-destination default voice id (null = use global default).
final destinationDefaultVoiceProvider =
    FutureProvider.family<String?, String>((ref, destId) {
  ref.watch(narrationRefreshProvider);
  return ref.watch(destinationNarrationRepositoryProvider)
      .destinationDefaultVoiceId(destId);
});
