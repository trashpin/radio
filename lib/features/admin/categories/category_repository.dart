import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/categories/location_category.dart';

/// Read/write access to the admin-manageable `categories` table (migration
/// 0039). Read-safe when Supabase isn't configured or the table doesn't exist
/// yet — callers fall back to the built-in [LocationType] taxonomy alone.
class CategoryRepository {
  const CategoryRepository();

  Future<List<LocationCategory>> _query({bool activeOnly = false}) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      var q = SupabaseService.client.from('categories').select();
      if (activeOnly) q = q.eq('active', true);
      final rows = await q.order('sort_order', ascending: true) as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(LocationCategory.fromJson)
          .toList();
    } catch (_) {
      return const []; // table may not exist until migration 0039 is applied
    }
  }

  Future<List<LocationCategory>> all() => _query();
  Future<List<LocationCategory>> active() => _query(activeOnly: true);

  Future<void> create(Map<String, dynamic> row) => _resilient(
        row,
        (r) => SupabaseService.client.from('categories').insert(r),
      );
  Future<void> update(String id, Map<String, dynamic> fields) => _resilient(
        fields,
        (r) => SupabaseService.client.from('categories').update(r).eq('id', id),
      );
  Future<void> delete(String id) =>
      SupabaseService.client.from('categories').delete().eq('id', id);

  /// Same forward-compatible pattern as [NearbyGemsRepository._resilient]:
  /// drops any column PostgREST reports as missing and retries, so editing
  /// never breaks before a newer migration is applied.
  Future<void> _resilient(
    Map<String, dynamic> row,
    Future<void> Function(Map<String, dynamic>) run,
  ) async {
    var current = Map<String, dynamic>.from(row);
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await run(current);
        return;
      } on PostgrestException catch (e) {
        final col = _missingColumn(e.message);
        if (col == null || !current.containsKey(col)) rethrow;
        current.remove(col);
      }
    }
    await run(current); // last resort — let a real error surface
  }

  static String? _missingColumn(String message) {
    final m = RegExp(r"'([a-zA-Z0-9_]+)' column").firstMatch(message);
    return m?.group(1);
  }
}

final categoryRepositoryProvider =
    Provider<CategoryRepository>((ref) => const CategoryRepository());

class CategoryRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final categoryRefreshProvider =
    NotifierProvider<CategoryRefresh, int>(CategoryRefresh.new);

/// Every category row (admin list) — built-ins + custom, active or not.
final allCategoriesProvider = FutureProvider<List<LocationCategory>>((ref) {
  ref.watch(categoryRefreshProvider);
  return ref.watch(categoryRepositoryProvider).all();
});

/// Active categories only — what pickers should merge with [LocationType].
final activeCategoriesProvider = FutureProvider<List<LocationCategory>>((ref) {
  ref.watch(categoryRefreshProvider);
  return ref.watch(categoryRepositoryProvider).active();
});

/// The full picker option list — built-in [LocationType]s plus any active
/// custom categories — ready for a category dropdown to consume directly.
final categoryOptionsProvider = Provider<List<CategoryOption>>((ref) {
  final custom = ref.watch(activeCategoriesProvider).value ?? const [];
  return combinedCategoryOptions(custom);
});
