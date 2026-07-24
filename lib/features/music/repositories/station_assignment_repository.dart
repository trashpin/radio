import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/data/read_repository.dart';
import 'package:explorer_os_mobile/core/data/supabase_tables.dart';
import 'package:explorer_os_mobile/core/services/connectivity_service.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/music/models/station_assignment.dart';

/// Repository for song↔station [StationAssignment]s (sync — assignments are
/// edited in the management tools).
class StationAssignmentRepository
    extends SupabaseSyncRepository<StationAssignment> {
  StationAssignmentRepository({required super.client, super.connectivity})
      : super(
          table: SupabaseTables.stationAssignments,
          fromJson: StationAssignment.fromJson,
          toJson: (assignment) => assignment.toJson(),
        );

  Future<List<StationAssignment>> forStation(String stationId) =>
      getWhere('station_id', stationId);

  Future<List<StationAssignment>> forSong(String songId) =>
      getWhere('song_id', songId);
}

final stationAssignmentRepositoryProvider =
    Provider<StationAssignmentRepository>((ref) {
  return StationAssignmentRepository(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
});
