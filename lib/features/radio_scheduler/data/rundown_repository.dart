import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/radio_scheduler/models/rundown.dart';

/// Reads/writes `rundowns` + `rundown_items` (Admin → Radio Scheduler).
/// Defensive: returns empty when Supabase/tables aren't there yet (migration
/// 0045), and resilient writes drop unknown columns and retry.
class RundownRepository {
  const RundownRepository();

  Future<List<Rundown>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('rundowns')
          .select()
          .order('created_at', ascending: false) as List;
      return rows.cast<Map<String, dynamic>>().map(Rundown.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<RundownItem>> items(String rundownId) async {
    if (!SupabaseService.isConfigured || rundownId.isEmpty) return const [];
    try {
      final rows = await SupabaseService.client
          .from('rundown_items')
          .select()
          .eq('rundown_id', rundownId)
          .order('sort_order', ascending: true) as List;
      return rows.cast<Map<String, dynamic>>().map(RundownItem.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Full rundown (metadata + ordered items) for the builder/player.
  Future<Rundown?> withItems(String id) async {
    final list = await all();
    Rundown? r;
    for (final x in list) {
      if (x.id == id) {
        r = x;
        break;
      }
    }
    if (r == null) return null;
    return r.copyWith(items: await items(id));
  }

  Future<String?> createRundown(String name) async {
    if (!SupabaseService.isConfigured) return null;
    final inserted = await SupabaseService.client
        .from('rundowns')
        .insert({'name': name.trim().isEmpty ? 'Untitled rundown' : name.trim()})
        .select('id')
        .single();
    return inserted['id']?.toString();
  }

  Future<void> updateRundown(String id, Map<String, dynamic> fields) =>
      _resilient(
          fields,
          (r) =>
              SupabaseService.client.from('rundowns').update(r).eq('id', id));

  Future<void> deleteRundown(String id) =>
      SupabaseService.client.from('rundowns').delete().eq('id', id);

  /// Whether an id belongs to an item that only exists locally (never saved).
  static bool isNewId(String id) => id.isEmpty || id.startsWith('tmp_');

  /// Inserts (new/local id) or updates a single item; returns its id.
  Future<String?> upsertItem(RundownItem item) async {
    if (!SupabaseService.isConfigured) return null;
    if (isNewId(item.id)) {
      final inserted = await SupabaseService.client
          .from('rundown_items')
          .insert(item.toWrite())
          .select('id')
          .single();
      return inserted['id']?.toString();
    }
    await _resilient(
        item.toWrite(),
        (r) => SupabaseService.client
            .from('rundown_items')
            .update(r)
            .eq('id', item.id));
    return item.id;
  }

  Future<void> deleteItem(String id) =>
      SupabaseService.client.from('rundown_items').delete().eq('id', id);

  /// Persists the current order (and enabled/name/duration) for every item.
  Future<void> saveItems(List<RundownItem> items) async {
    if (!SupabaseService.isConfigured) return;
    for (var i = 0; i < items.length; i++) {
      await upsertItem(items[i].copyWith(sortOrder: i));
    }
  }

  Future<void> _resilient(
    Map<String, dynamic> row,
    Future<void> Function(Map<String, dynamic>) run,
  ) async {
    final current = Map<String, dynamic>.from(row);
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        await run(current);
        return;
      } on PostgrestException catch (e) {
        final col = RegExp(r"'([a-zA-Z0-9_]+)' column")
            .firstMatch(e.message)
            ?.group(1);
        if (col == null || !current.containsKey(col)) rethrow;
        current.remove(col);
      }
    }
    await run(current);
  }
}

final rundownRepositoryProvider =
    Provider<RundownRepository>((ref) => const RundownRepository());

class RundownRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final rundownRefreshProvider =
    NotifierProvider<RundownRefresh, int>(RundownRefresh.new);

/// All rundowns (newest first). Bump [rundownRefreshProvider] after a write.
final rundownsProvider = FutureProvider<List<Rundown>>((ref) {
  ref.watch(rundownRefreshProvider);
  return ref.watch(rundownRepositoryProvider).all();
});

/// A single rundown with its ordered items.
final rundownWithItemsProvider =
    FutureProvider.family<Rundown?, String>((ref, id) {
  ref.watch(rundownRefreshProvider);
  return ref.watch(rundownRepositoryProvider).withItems(id);
});
