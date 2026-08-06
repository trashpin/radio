import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/gps/models/geofence.dart';

/// Read/write access to `geofences` (migration 0043). Read-safe when
/// Supabase isn't configured or the table doesn't exist yet — callers get
/// an empty list rather than an error, matching every other repository in
/// this codebase.
class GeofenceRepository {
  const GeofenceRepository();

  Future<List<Geofence>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows =
          await SupabaseService.client.from('geofences').select() as List;
      return rows.cast<Map<String, dynamic>>().map(Geofence.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Geofence>> forLocation(String locationId) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('geofences')
          .select()
          .eq('location_id', locationId) as List;
      return rows.cast<Map<String, dynamic>>().map(Geofence.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> create(Map<String, dynamic> row) => _resilient(
        row,
        (r) => SupabaseService.client.from('geofences').insert(r),
      );
  Future<void> update(String id, Map<String, dynamic> fields) => _resilient(
        fields,
        (r) =>
            SupabaseService.client.from('geofences').update(r).eq('id', id),
      );
  Future<void> delete(String id) =>
      SupabaseService.client.from('geofences').delete().eq('id', id);

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

final geofenceRepositoryProvider =
    Provider<GeofenceRepository>((ref) => const GeofenceRepository());

class GeofenceRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final geofenceRefreshProvider =
    NotifierProvider<GeofenceRefresh, int>(GeofenceRefresh.new);

/// Every geofence (admin view + the live hierarchy engine both read this —
/// filtering to "active" and "within region" happens in the pure engine
/// functions, not here, so the engine stays easy to unit test against a
/// plain list).
final geofencesProvider = FutureProvider<List<Geofence>>((ref) {
  ref.watch(geofenceRefreshProvider);
  return ref.watch(geofenceRepositoryProvider).all();
});

/// Every geofence for one location (admin editing view).
final geofencesForLocationProvider =
    FutureProvider.family<List<Geofence>, String>((ref, locationId) {
  ref.watch(geofenceRefreshProvider);
  return ref.watch(geofenceRepositoryProvider).forLocation(locationId);
});
