import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/db_tools/db_tools.dart';

/// Read/maintenance access for the Database Tools center — all via PostgREST
/// (no raw SQL), so it stays within the app's RLS policies.
class DbToolsRepository {
  const DbToolsRepository();

  /// Exact row count, or -1 if the table is unreachable/missing.
  Future<int> count(String table) async {
    if (!SupabaseService.isConfigured) return -1;
    try {
      return await SupabaseService.client.from(table).count(CountOption.exact);
    } catch (_) {
      return -1;
    }
  }

  /// Recent rows from a table (for the browser / export).
  Future<List<Map<String, dynamic>>> rows(String table, {int limit = 100}) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final res = await SupabaseService.client.from(table).select().limit(limit)
          as List;
      return res.cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> deleteRow(String table, dynamic id) =>
      SupabaseService.client.from(table).delete().eq('id', id);

  /// Runs a maintenance CHECK — returns matching rows (limited).
  Future<List<Map<String, dynamic>>> runCheck(MaintenanceScript s,
      {int limit = 200}) async {
    if (!SupabaseService.isConfigured) return const [];
    var q = SupabaseService.client.from(s.table).select();
    q = switch (s.op) {
      FilterOp.isNull => q.isFilter(s.column, null),
      FilterOp.eq => q.eq(s.column, s.value as Object),
    };
    final res = await q.limit(limit) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Applies a maintenance FIX to matching rows; returns how many matched first.
  Future<int> runFix(MaintenanceScript s) async {
    final matches = await runCheck(s, limit: 1000);
    if (matches.isEmpty || s.update == null) return 0;
    var q = SupabaseService.client.from(s.table).update(s.update!);
    q = switch (s.op) {
      FilterOp.isNull => q.isFilter(s.column, null),
      FilterOp.eq => q.eq(s.column, s.value as Object),
    };
    await q;
    return matches.length;
  }
}

final dbToolsRepositoryProvider =
    Provider<DbToolsRepository>((ref) => const DbToolsRepository());

/// Dashboard counts (table name → count) for the headline tables.
final dbCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  final repo = ref.watch(dbToolsRepositoryProvider);
  final out = <String, int>{};
  for (final t in kDashboardTables) {
    out[t.name] = await repo.count(t.name);
  }
  return out;
});
