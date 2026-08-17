import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException;

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

  Future<void> create(Map<String, dynamic> row) => _resilient(
        row,
        (r) => SupabaseService.client.from('counties').insert(r),
      );

  Future<void> update(String id, Map<String, dynamic> fields) => _resilient(
        fields,
        (r) => SupabaseService.client.from('counties').update(r).eq('id', id),
      );

  Future<void> delete(String id) =>
      SupabaseService.client.from('counties').delete().eq('id', id);

  /// Runs a write, and if it fails only because a column isn't in the schema
  /// cache yet, drops that column and retries — matches the same pattern used
  /// for `nearby_gems` so County Profile edits never break on a stale schema
  /// cache.
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
    await run(current);
  }

  static String? _missingColumn(String message) {
    final m = RegExp(r"'([a-zA-Z0-9_]+)' column").firstMatch(message);
    return m?.group(1);
  }

  static const String bucket = 'media';

  /// Uploads a county seal/hero image to the `media` bucket and returns its
  /// public URL.
  Future<String> uploadImage(
    Uint8List bytes,
    String filename, {
    String contentType = 'image/jpeg',
  }) async {
    final client = SupabaseService.client;
    final slug = filename.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]+'), '_');
    final path = 'counties/${DateTime.now().millisecondsSinceEpoch}_$slug';
    await client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return client.storage.from(bucket).getPublicUrl(path);
  }
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
