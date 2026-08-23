import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';

/// Known reference species/features for one or more `species.category`
/// values, combined and de-duplicated — the "is it one of these?" list
/// DISCOVER shows before falling back to the photo/AI flow. [categoriesKey]
/// is a comma-joined category list (a plain String param keeps this a
/// simple, cacheable Riverpod family — a List param wouldn't compare equal
/// across rebuilds).
final forestDiscoverKnownMatchesProvider =
    FutureProvider.family<List<Species>, String>((ref, categoriesKey) async {
  final categories = categoriesKey.split(',').where((c) => c.isNotEmpty).toList();
  if (categories.isEmpty) return const [];
  final repo = ref.watch(speciesRepositoryProvider);
  final results = await Future.wait(categories.map(repo.byCategory));
  final seen = <String>{};
  final combined = <Species>[];
  for (final list in results) {
    for (final s in list) {
      if (seen.add(s.id)) combined.add(s);
    }
  }
  combined.sort((a, b) => a.commonName.compareTo(b.commonName));
  return combined;
});
