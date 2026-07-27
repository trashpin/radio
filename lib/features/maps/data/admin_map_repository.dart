import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/maps/models/map_poi.dart';

/// Read/write repository for POIs in `map_locations` (admin Map Editor).
///
/// Insert works with the public policy; update/delete require the policies
/// added in migration 0009. All writes are best-effort — the editor keeps an
/// optimistic local copy so the map stays usable even before migration.
class AdminMapRepository {
  const AdminMapRepository(this._client);
  final dynamic _client; // SupabaseClient

  static const _table = SupabaseTables.mapLocations;

  Future<List<MapPoi>> byPark(String parkCode) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('park_code', parkCode)
        .order('name') as List;
    return _parse(rows);
  }

  /// All POIs (every park). Used by the Map Editor so nothing is hidden by a
  /// park_code filter.
  Future<List<MapPoi>> all() async {
    final rows =
        await _client.from(_table).select().order('name') as List;
    return _parse(rows);
  }

  /// Maps rows to POIs, skipping any without valid numeric coordinates (so one
  /// bad row never blanks the whole map).
  List<MapPoi> _parse(List rows) {
    final out = <MapPoi>[];
    for (final r in rows) {
      final lat = r['latitude'], lng = r['longitude'];
      if (lat is! num || lng is! num) continue;
      out.add(MapPoi.fromJson(r as Map<String, dynamic>));
    }
    return out;
  }

  /// Insert (no id) or update (has id). Returns the saved row.
  Future<MapPoi> upsert(MapPoi poi) async {
    final payload = Map<String, dynamic>.from(poi.toJson())
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    final List rows;
    if (poi.id.isEmpty) {
      payload.remove('id');
      rows = await _client.from(_table).insert(payload).select() as List;
    } else {
      rows = await _client
          .from(_table)
          .update(payload)
          .eq('id', poi.id)
          .select() as List;
    }
    return MapPoi.fromJson(rows.first);
  }

  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }
}

final adminMapRepositoryProvider = Provider<AdminMapRepository>((ref) {
  return AdminMapRepository(ref.watch(supabaseClientProvider));
});

/// POIs for the Map Editor — every `map_locations` row (not filtered by park),
/// so nothing is hidden. Rows without valid coordinates are skipped.
final mapEditorPoisProvider = FutureProvider<List<MapPoi>>((ref) async {
  try {
    return await ref.watch(adminMapRepositoryProvider).all();
  } catch (_) {
    return const <MapPoi>[];
  }
});
