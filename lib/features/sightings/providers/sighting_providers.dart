import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/sightings/data/sighting_repository.dart';
import 'package:explorer_os_mobile/features/sightings/models/explorer_sighting.dart';

/// Recent sightings (newest first), shared by the Map layer, the "recent
/// sightings" picker, and the admin list. Supports optimistic insert so a
/// just-saved sighting appears immediately.
final recentSightingsProvider =
    AsyncNotifierProvider<RecentSightings, List<ExplorerSighting>>(
        RecentSightings.new);

class RecentSightings extends AsyncNotifier<List<ExplorerSighting>> {
  @override
  Future<List<ExplorerSighting>> build() {
    return ref.watch(sightingRepositoryProvider).recent();
  }

  /// Optimistically prepend a newly-saved sighting.
  void add(ExplorerSighting sighting) {
    final current = state.value ?? const [];
    state = AsyncData([sighting, ...current]);
  }

  Future<void> remove(String id) async {
    await ref.read(sightingRepositoryProvider).deleteSighting(id);
    state = AsyncData(
      (state.value ?? const []).where((s) => s.id != id).toList(),
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(sightingRepositoryProvider).recent(),
    );
  }
}

/// Sightings scoped to a destination (for the Map / destination detail).
final sightingsByDestinationProvider =
    FutureProvider.family<List<ExplorerSighting>, String>((ref, destinationId) {
  return ref.watch(sightingRepositoryProvider).byDestination(destinationId);
});
