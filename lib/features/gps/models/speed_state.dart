import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';

/// Speed plus the classifications derived from it.
///
/// The SpeedService converts a raw meters/second reading into this value
/// object, tagging the inferred [travelMode] (walking/biking/driving/
/// stationary) and [movementState]. Convenience getters expose km/h and mph.
class SpeedState {
  const SpeedState({
    required this.metersPerSecond,
    required this.movementState,
    required this.travelMode,
  });

  final double metersPerSecond;
  final MovementState movementState;
  final TravelMode travelMode;

  double get kmh => metersPerSecond * 3.6;
  double get mph => metersPerSecond * 2.2369362921;

  bool get isMoving => movementState == MovementState.moving;

  static const stationary = SpeedState(
    metersPerSecond: 0,
    movementState: MovementState.idle,
    travelMode: TravelMode.stationary,
  );
}
