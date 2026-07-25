import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/story.dart';

/// Read repository for [Story] content. Adds park/stop relationship queries.
class StoryRepository extends SupabaseReadRepository<Story> {
  StoryRepository({
    required super.client,
    super.connectivity,
  }) : super(table: SupabaseTables.stories, fromJson: Story.fromJson);

  /// Stories within a destination (Base44 `destination_id`).
  Future<List<Story>> byDestination(String destinationId) =>
      getWhere('destination_id', destinationId);

  /// Backwards-compatible alias — Base44 keys stories on `destination_id`.
  Future<List<Story>> byPark(String destinationId) =>
      byDestination(destinationId);
  Future<List<Story>> byStop(String stopId) => getWhere('stop_id', stopId);
}

final storyRepositoryProvider = Provider<StoryRepository>((ref) {
  return StoryRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// Stories for a given destination id.
final storiesByDestinationProvider =
    FutureProvider.family<List<Story>, String>((ref, destinationId) {
  return ref.watch(storyRepositoryProvider).byDestination(destinationId);
});

/// Backwards-compatible alias (destinations are the app's "parks").
final storiesByParkProvider = storiesByDestinationProvider;
