import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/user_favorite.dart';

/// Repository for USER-OWNED favorites.
///
/// Extends [SupabaseSyncRepository], so it can both read favorites and sync
/// changes (add/remove) back to Supabase via the inherited `upsert`/`deleteById`
/// — the write capability content repositories intentionally lack. This is the
/// backend counterpart to the in-memory `favoritesProvider` used by the UI; the
/// two will be reconciled when auth/sync is wired up.
class UserFavoriteRepository extends SupabaseSyncRepository<UserFavorite> {
  UserFavoriteRepository({
    required super.client,
    super.connectivity,
  }) : super(
          table: SupabaseTables.userFavorites,
          fromJson: UserFavorite.fromJson,
          toJson: (favorite) => favorite.toJson(),
        );

  /// Favorites belonging to a specific user.
  Future<List<UserFavorite>> byUser(String userId) =>
      getWhere('user_id', userId);
}

final userFavoriteRepositoryProvider =
    Provider<UserFavoriteRepository>((ref) {
  return UserFavoriteRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// Favorites for a given user id.
final userFavoritesByUserProvider =
    FutureProvider.family<List<UserFavorite>, String>((ref, userId) {
  return ref.watch(userFavoriteRepositoryProvider).byUser(userId);
});
