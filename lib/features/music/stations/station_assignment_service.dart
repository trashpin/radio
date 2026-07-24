import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/music/models/station_assignment.dart';
import 'package:explorer_os_mobile/features/music/repositories/station_assignment_repository.dart';

/// Manages which songs air on which stations (the many-to-many mapping the
/// Radio Engine's playlist is built from).
class StationAssignmentService {
  const StationAssignmentService(this._repository);
  final StationAssignmentRepository _repository;

  Future<List<StationAssignment>> forStation(String stationId) =>
      _repository.forStation(stationId);

  Future<void> assign(
    String id,
    String songId,
    String stationId, {
    double weight = 1.0,
  }) {
    return _repository.upsert(StationAssignment(
      id: id,
      songId: songId,
      stationId: stationId,
      weight: weight,
    ));
  }

  Future<void> unassign(String assignmentId) =>
      _repository.deleteById(assignmentId);
}

final stationAssignmentServiceProvider =
    Provider<StationAssignmentService>((ref) {
  return StationAssignmentService(
    ref.watch(stationAssignmentRepositoryProvider),
  );
});
