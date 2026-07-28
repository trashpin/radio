import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/audio_studio/logic/audio_audit.dart';
import 'package:explorer_os_mobile/features/admin/audio_studio/models/audio_asset.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/data/media_manager_repository.dart';
import 'package:explorer_os_mobile/features/content_generator/data/content_generator_repository.dart';
import 'package:explorer_os_mobile/features/content_generator/models/content_models.dart';

/// A default voice assigned to a content category (Voice Library).
class VoiceAssignment {
  const VoiceAssignment({
    required this.category,
    this.voiceId,
    this.voiceName,
    this.provider = TtsProvider.elevenlabs,
  });

  final String category;
  final String? voiceId;
  final String? voiceName;
  final TtsProvider provider;

  factory VoiceAssignment.fromJson(Map<String, dynamic> j) => VoiceAssignment(
        category: (j['category'] ?? '') as String,
        voiceId: j['voice_id'] as String?,
        voiceName: j['voice_name'] as String?,
        provider: TtsProvider.fromId(j['provider'] as String?),
      );
}

/// Data access + job orchestration for the Audio Production Studio.
class AudioProductionRepository {
  const AudioProductionRepository();

  Future<List<AudioAsset>> assets() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('audio_assets')
          .select()
          .order('created_at', ascending: false) as List;
      return rows.cast<Map<String, dynamic>>().map(AudioAsset.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<VoiceAssignment>> voiceDefaults() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('voice_category_defaults')
          .select() as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(VoiceAssignment.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> setVoiceForCategory(
    VoiceCategory category,
    String voiceId,
    String voiceName,
    TtsProvider provider,
  ) async {
    await SupabaseService.client.from('voice_category_defaults').upsert({
      'category': category.id,
      'voice_id': voiceId,
      'voice_name': voiceName,
      'provider': provider.id,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteAsset(String id) =>
      SupabaseService.client.from('audio_assets').delete().eq('id', id);

  /// Enqueues an audio-generation job (drained by the narration worker).
  Future<void> enqueueAudioJob({
    required String destination,
    String? notes,
  }) {
    final job = GenerationJob(
      id: '',
      destination: destination,
      jobType: JobType.audio,
      status: JobStatus.pending,
      notes: notes,
    );
    return SupabaseService.client
        .from('generation_jobs')
        .insert(job.toInsert());
  }

  /// Publishes a destination: enqueues the full narration set for its code.
  Future<void> publishDestination(String destinationCode, String name) {
    const sections = [
      'welcome', 'history', 'wildlife', 'plants', 'stories', 'safety',
      'accessibility', 'hidden_gems', 'departure',
    ];
    return enqueueAudioJob(
      destination: name,
      notes: 'audio:publish;code=$destinationCode;'
          'sections=${sections.join('|')}',
    );
  }
}

final audioProductionRepositoryProvider =
    Provider<AudioProductionRepository>((ref) => const AudioProductionRepository());

/// Bump to refresh audio assets after an action.
final audioRefreshProvider =
    NotifierProvider<AudioRefresh, int>(AudioRefresh.new);

class AudioRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final audioAssetsProvider = FutureProvider<List<AudioAsset>>((ref) {
  ref.watch(audioRefreshProvider);
  return ref.watch(audioProductionRepositoryProvider).assets();
});

final voiceCategoryDefaultsProvider =
    FutureProvider<Map<String, VoiceAssignment>>((ref) async {
  ref.watch(audioRefreshProvider);
  final list = await ref.watch(audioProductionRepositoryProvider).voiceDefaults();
  return {for (final v in list) v.category: v};
});

/// Every record that can have narration audio, normalized to [AudioRecordRef]
/// (aggregated from `species` + `map_locations` via the Media Manager records).
final audioRecordsProvider = Provider<List<AudioRecordRef>>((ref) {
  final records = ref.watch(mediaRecordsProvider);
  return [
    for (final r in records)
      AudioRecordRef(
        id: r.id,
        category: VoiceCategory.fromToken(r.category ?? r.type.name),
        title: r.title,
        destinationCode: r.destinationId,
        existingAudioUrl: r.audioUrl,
      ),
  ];
});

/// Number of pending/in-flight audio jobs in the queue.
final audioQueueCountProvider = Provider<int>((ref) {
  final jobs = ref.watch(generationJobsProvider).value ?? const [];
  return jobs
      .where((j) => j.jobType == JobType.audio && !j.status.isTerminal)
      .length;
});

final audioAuditProvider = Provider<List<AudioRecordAudit>>((ref) {
  final records = ref.watch(audioRecordsProvider);
  final assets = ref.watch(audioAssetsProvider).value ?? const [];
  return auditAudio(records, assets);
});

final audioDashboardProvider = Provider<AudioDashboardStats>((ref) {
  final records = ref.watch(audioRecordsProvider);
  final assets = ref.watch(audioAssetsProvider).value ?? const [];
  final queued = ref.watch(audioQueueCountProvider);
  return computeAudioDashboard(records, assets, queued: queued);
});
