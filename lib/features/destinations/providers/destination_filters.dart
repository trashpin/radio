import 'package:flutter_riverpod/flutter_riverpod.dart';
// StateProvider is a "legacy" provider in Riverpod 3.x — imported explicitly.
import 'package:flutter_riverpod/legacy.dart';

import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// The category filters shown as chips on the Explore screen.
///
/// [matchValue] is the backend `category` token this chip selects (null = all).
enum DestinationCategory {
  all('All', null),
  parks('Parks', 'park'),
  trails('Trails', 'trail'),
  scenicDrives('Scenic Drives', 'scenic');

  const DestinationCategory(this.label, this.matchValue);

  final String label;
  final String? matchValue;
}

/// Current free-text search query (parks, places, routes…).
final destinationQueryProvider = StateProvider<String>((ref) => '');

/// Currently selected category chip.
final destinationCategoryProvider =
    StateProvider<DestinationCategory>((ref) => DestinationCategory.all);

/// Whether any filter (search text or non-"All" category) is active.
final destinationHasActiveFilterProvider = Provider<bool>((ref) {
  final query = ref.watch(destinationQueryProvider);
  final category = ref.watch(destinationCategoryProvider);
  return query.trim().isNotEmpty || category != DestinationCategory.all;
});

/// The destination shown in the Featured section — the first flagged
/// `featured`, falling back to the first available. Null when there are none.
final featuredDestinationProvider = Provider<Destination?>((ref) {
  final all = ref.watch(destinationsProvider).value ?? const [];
  if (all.isEmpty) return null;
  for (final d in all) {
    if (d.featured) return d;
  }
  return all.first;
});

/// The list rendered under "Popular Near You" / search results: the loaded
/// destinations with the active search + category filters applied.
///
/// Keeping this pure filtering here (not in the widget) is the "separate UI from
/// business logic" goal — the screen just renders whatever this returns.
final filteredDestinationsProvider = Provider<List<Destination>>((ref) {
  final all = ref.watch(destinationsProvider).value ?? const [];
  final query = ref.watch(destinationQueryProvider).trim().toLowerCase();
  final category = ref.watch(destinationCategoryProvider);

  return all.where((d) {
    final matchesCategory = category.matchValue == null ||
        (d.category?.toLowerCase() == category.matchValue);

    final matchesQuery = query.isEmpty ||
        d.name.toLowerCase().contains(query) ||
        (d.location?.toLowerCase().contains(query) ?? false) ||
        (d.description?.toLowerCase().contains(query) ?? false);

    return matchesCategory && matchesQuery;
  }).toList(growable: false);
});
