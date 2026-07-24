import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';

/// A high-level summary of HOW the user is travelling right now.
///
/// Aggregates movement + mode + "parked" into one small object the engine and
/// TravelContext can carry. Distinct from `SpeedState` (a raw measurement) —
/// this is the interpreted travel status, including cumulative distance.
class TravelState {
  const TravelState({
    required this.movementState,
    required this.travelMode,
    required this.isParked,
    this.distanceTravelledMeters = 0,
  });

  final MovementState movementState;
  final TravelMode travelMode;
  final bool isParked;
  final double distanceTravelledMeters;

  bool get isMoving => movementState == MovementState.moving;

  static const idle = TravelState(
    movementState: MovementState.idle,
    travelMode: TravelMode.stationary,
    isParked: false,
  );
}
