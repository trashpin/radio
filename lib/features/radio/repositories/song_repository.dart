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
