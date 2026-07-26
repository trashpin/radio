import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

/// Read repository for [Song] content (a station's playlist).
class SongRepository extends SupabaseReadRepository<Song> {
  SongRepository({
    required super.client,
    super.connectivity,
  }) : super(table: SupabaseTables.songs, fromJson: Song.fromJson);

  Future<List<Song>> byStation(String stationId) =>
      getWhere('station_id', stationId);

  /// Active songs for the radio playlist, optionally filtered by park or
  /// station (admin-uploaded rows use `park_code` + `station`). This is the
  /// dynamic source: songs uploaded in the admin appear here with no redeploy.
  Future<List<Song>> activeSongs({String? parkCode, String? station}) async {
    var q = client.from(table).select().eq('is_active', true);
    if (parkCode != null && parkCode.isNotEmpty) q = q.eq('park_code', parkCode);
    if (station != null && station.isNotEmpty) q = q.eq('station', station);
    final rows = await q.order('created_at') as List;
    return rows
        .map((r) => Song.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }
}

final songRepositoryProvider = Provider<SongRepository>((ref) {
  return SongRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});

/// Songs for a given station id (playlist).
final songsByStationProvider =
    FutureProvider.family<List<Song>, String>((ref, stationId) {
  return ref.watch(songRepositoryProvider).byStation(stationId);
});
