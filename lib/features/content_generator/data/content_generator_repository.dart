import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/content_generator/models/content_models.dart';

/// Data access for the Content Generator: the knowledge base + the job queue.
class ContentGeneratorRepository {
  const ContentGeneratorRepository();

  // ── Knowledge base ──
  Future<List<KnowledgeFact>> facts() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('knowledge_base')
          .select()
          .order('created_at', ascending: false) as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(KnowledgeFact.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> approveFact(String id) => SupabaseService.client
      .from('knowledge_base')
      .update({'approved': true, 'verified': true}).eq('id', id);

  Future<void> deleteFact(String id) =>
      SupabaseService.client.from('knowledge_base').delete().eq('id', id);

  // ── Jobs ──
  Future<List<GenerationJob>> jobs() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('generation_jobs')
          .select()
          .order('created_at', ascending: false) as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(GenerationJob.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> enqueue(GenerationJob job) =>
      SupabaseService.client.from('generation_jobs').insert(job.toInsert());

  Future<void> retry(String id) => SupabaseService.client
      .from('generation_jobs')
      .update({'status': JobStatus.pending.dbValue, 'message': null}).eq('id', id);

  Future<void> deleteJob(String id) =>
      SupabaseService.client.from('generation_jobs').delete().eq('id', id);
}

final contentGeneratorRepositoryProvider =
    Provider<ContentGeneratorRepository>((ref) => const ContentGeneratorRepository());

final knowledgeBaseProvider = FutureProvider<List<KnowledgeFact>>((ref) {
  ref.watch(contentRefreshProvider);
  return ref.watch(contentGeneratorRepositoryProvider).facts();
});

final generationJobsProvider = FutureProvider<List<GenerationJob>>((ref) {
  ref.watch(contentRefreshProvider);
  return ref.watch(contentGeneratorRepositoryProvider).jobs();
});

class ContentRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final contentRefreshProvider =
    NotifierProvider<ContentRefresh, int>(ContentRefresh.new);
