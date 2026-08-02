import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/models/area_species_mapping.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';

/// Every species across all the `species.category` values mapped to
/// [areaCategoryToken] (see [areaSpeciesCategoryMap]), merged and sorted by
/// common name. Empty for a token with no mapping (e.g. History/Nature/
/// Geology use `area_discovery_content` instead — see Phase 3).
final areaSpeciesProvider =
    FutureProvider.family<List<Species>, String>((ref, areaCategoryToken) async {
  final categories = areaSpeciesCategoryMap[areaCategoryToken] ?? const [];
  if (categories.isEmpty) return const [];
  final repo = ref.watch(speciesRepositoryProvider);
  final lists = await Future.wait(categories.map(repo.byCategory));
  final all = lists.expand((l) => l).toList()
    ..sort((a, b) => a.commonName.compareTo(b.commonName));
  return all;
});
