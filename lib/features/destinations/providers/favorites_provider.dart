import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// Holds the set of favorited destination IDs.
///
/// Favorites are USER data (not backend destination content), so they live in
/// app state rather than being fetched. For now this is in-memory; a future
/// iteration can persist it (local storage or a per-user Supabase table)
/// without changing any of the widgets that depend on this notifier.
class FavoritesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  /// Adds the id if absent, removes it if present.
  void toggle(String destinationId) {
    final next = Set<String>.from(state);
    if (!next.add(destinationId)) {
      next.remove(destinationId);
    }
    state = next;
  }

  bool isFavorite(String destinationId) => state.contains(destinationId);
}

/// The favorites notifier — widgets watch this to reflect/toggle favorite state.
final favoritesProvider =
    NotifierProvider<FavoritesNotifier, Set<String>>(FavoritesNotifier.new);

/// The favorited destinations, resolved against the loaded destination list.
///
/// Reused by the Explore "Favorites" section today and ready to power the
/// Profile screen's Favorites list later.
final favoriteDestinationsProvider = Provider<List<Destination>>((ref) {
  final ids = ref.watch(favoritesProvider);
  final all = ref.watch(destinationsProvider).value ?? const [];
  return all.where((d) => ids.contains(d.id)).toList(growable: false);
});
