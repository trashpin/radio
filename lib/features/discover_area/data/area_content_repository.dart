import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/discover_area/models/area_content_block.dart';

/// Read/write access to `area_discovery_content` (migration 0042). Read-safe
/// when Supabase isn't configured or the table doesn't exist yet.
class AreaContentRepository {
  const AreaContentRepository();

  Future<List<AreaContentBlock>> forLocation(String locationId) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('area_discovery_content')
          .select()
          .eq('location_id', locationId)
          .order('category_token', ascending: true)
          .order('sort_order', ascending: true) as List;
      return rows.cast<Map<String, dynamic>>().map(AreaContentBlock.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<AreaContentBlock>> forCategory(
    String locationId,
    String categoryToken, {
    bool activeOnly = true,
  }) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      var q = SupabaseService.client
          .from('area_discovery_content')
          .select()
          .eq('location_id', locationId)
          .eq('category_token', categoryToken);
      if (activeOnly) q = q.eq('active', true);
      final rows = await q.order('sort_order', ascending: true) as List;
      return rows.cast<Map<String, dynamic>>().map(AreaContentBlock.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> create(Map<String, dynamic> row) => _resilient(
        row,
        (r) => SupabaseService.client.from('area_discovery_content').insert(r),
      );
  Future<void> update(String id, Map<String, dynamic> fields) => _resilient(
        fields,
        (r) => SupabaseService.client
            .from('area_discovery_content')
            .update(r)
            .eq('id', id),
      );
  Future<void> delete(String id) => SupabaseService.client
      .from('area_discovery_content')
      .delete()
      .eq('id', id);

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
        final m = RegExp(r"'([a-zA-Z0-9_]+)' column").firstMatch(e.message);
        final col = m?.group(1);
        if (col == null || !current.containsKey(col)) rethrow;
        current.remove(col);
      }
    }
    await run(current);
  }
}

final areaContentRepositoryProvider =
    Provider<AreaContentRepository>((ref) => const AreaContentRepository());

class AreaContentRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final areaContentRefreshProvider =
    NotifierProvider<AreaContentRefresh, int>(AreaContentRefresh.new);

/// Every content block for one area (admin management view).
final areaContentForLocationProvider =
    FutureProvider.family<List<AreaContentBlock>, String>((ref, locationId) {
  ref.watch(areaContentRefreshProvider);
  return ref.watch(areaContentRepositoryProvider).forLocation(locationId);
});

/// Active blocks for one area + category, in play order — what the traveler-
/// facing category experience screen consumes.
final areaContentForCategoryProvider = FutureProvider.family<
    List<AreaContentBlock>, ({String locationId, String categoryToken})>((
  ref,
  key,
) {
  ref.watch(areaContentRefreshProvider);
  return ref
      .watch(areaContentRepositoryProvider)
      .forCategory(key.locationId, key.categoryToken);
});
