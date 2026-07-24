import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/narration.dart';

/// Read repository for [Narration] audio content. Adds the story relationship
/// query used by the Radio/Stories players.
class NarrationRepository extends SupabaseReadRepository<Narration> {
  NarrationRepository({
    required super.client,
    super.connectivity,
  }) : super(table: SupabaseTables.narrations, fromJson: Narration.fromJson);

  Future<List<Narration>> byStory(String storyId) =>
      getWhere('story_id', storyId);
}

final narrationRepositoryProvider = Provider<NarrationRepository>((ref) {
  return NarrationRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// Narrations for a given story id.
final narrationsByStoryProvider =
    FutureProvider.family<List<Narration>, String>((ref, storyId) {
  return ref.watch(narrationRepositoryProvider).byStory(storyId);
});
