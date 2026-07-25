import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/knowledge_article.dart';

/// Read repository for Base44 `knowledge_articles` (AI Ranger knowledge).
/// Built on the generic base; adds destination/stop relationship queries.
class KnowledgeArticleRepository
    extends SupabaseReadRepository<KnowledgeArticle> {
  KnowledgeArticleRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.knowledgeArticles,
          fromJson: KnowledgeArticle.fromJson,
        );

  Future<List<KnowledgeArticle>> byDestination(String destinationId) =>
      getWhere('destination_id', destinationId);
  Future<List<KnowledgeArticle>> byStop(String stopId) =>
      getWhere('stop_id', stopId);
}

final knowledgeArticleRepositoryProvider =
    Provider<KnowledgeArticleRepository>((ref) {
  return KnowledgeArticleRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// Knowledge articles for a given destination id.
final knowledgeArticlesByDestinationProvider =
    FutureProvider.family<List<KnowledgeArticle>, String>((ref, destinationId) {
  return ref
      .watch(knowledgeArticleRepositoryProvider)
      .byDestination(destinationId);
});
