import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config.dart';

/// Reads/writes the `counties` table (Admin → County Manager). Defensive:
/// returns [] when the table doesn't exist yet (migration 0032), so the radio
/// falls back to the built-in county personalities.
class CountyConfigRepository {
  const CountyConfigRepository();

  Future<List<CountyConfig>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('counties')
          .select()
          .order('name', ascending: true) as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(CountyConfig.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> create(Map<String, dynamic> row) =>
      SupabaseService.client.from('counties').insert(row);

  Future<void> update(String id, Map<String, dynamic> fields) =>
      SupabaseService.client.from('counties').update(fields).eq('id', id);

  Future<void> delete(String id) =>
      SupabaseService.client.from('counties').delete().eq('id', id);
}

final countyConfigRepositoryProvider =
    Provider<CountyConfigRepository>((ref) => const CountyConfigRepository());

class CountyConfigRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final countyConfigRefreshProvider =
    NotifierProvider<CountyConfigRefresh, int>(CountyConfigRefresh.new);

final countyConfigsProvider = FutureProvider<List<CountyConfig>>((ref) {
  ref.watch(countyConfigRefreshProvider);
  return ref.watch(countyConfigRepositoryProvider).all();
});

/// county-name (lowercase) → custom welcome greeting, from the admin table.
/// Empty until the table is populated; the radio then uses built-in defaults.
final countyGreetingsProvider = Provider<Map<String, String>>((ref) {
  final configs = ref.watch(countyConfigsProvider).value ?? const [];
  return {
    for (final c in configs)
      if ((c.welcome ?? '').trim().isNotEmpty) c.key: c.welcome!.trim(),
  };
});
