import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/ocala_forest/discover/data/forest_discovery_repository.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/models/forest_discovery_report.dart';

/// All publicly-visible DISCOVER reports (already generalized/filtered by
/// the `forest_discovery_reports_public` view — see migration 0051).
final forestDiscoveriesProvider = FutureProvider<List<ForestDiscoveryReport>>((ref) {
  return ref.watch(forestDiscoveryRepositoryProvider).getAll();
});

/// Recent discoveries linked to one species (spec §12 — "RECENT
/// DISCOVERIES" on an existing wildlife page). Linkage is the deterministic
/// exact-name match computed server-side (migration 0051's
/// forest_discovery_reports_match_species trigger), never an AI guess.
final forestDiscoveriesForSpeciesProvider =
    FutureProvider.family<List<ForestDiscoveryReport>, String>((ref, speciesId) async {
  final all = await ref.watch(forestDiscoveriesProvider.future);
  return [for (final d in all) if (d.speciesId == speciesId) d];
});
