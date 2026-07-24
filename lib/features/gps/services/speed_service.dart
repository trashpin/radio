import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/speed_state.dart';

/// Classifies a raw speed into a [SpeedState] (movement + travel mode).
///
/// WHY THIS EXISTS: turning meters/second into meaning ("walking" vs "driving",
/// "moving" vs "stopped") is a policy that many parts of the engine need. It
/// lives here once, behind tunable thresholds, so classification is consistent
/// and testable.
class SpeedService {
  const SpeedService({
    this.movingThresholdMps = 0.5,
    this.walkingMaxMps = 2.2,
    this.bikingMaxMps = 8.0,
  });

  /// Below this, the user is considered stopped.
  final double movingThresholdMps;

  /// Upper bound for "walking".
  final double walkingMaxMps;

  /// Upper bound for "biking"; above it is "driving".
  final double bikingMaxMps;

  SpeedState classify(double? metersPerSecond) {
    final mps = metersPerSecond ?? 0;

    if (mps < movingThresholdMps) {
      return SpeedState(
        metersPerSecond: mps,
        movementState: MovementState.stopped,
        travelMode: TravelMode.stationary,
      );
    }

    final TravelMode mode;
    if (mps <= walkingMaxMps) {
      mode = TravelMode.walking;
    } else if (mps <= bikingMaxMps) {
      mode = TravelMode.biking;
    } else {
      mode = TravelMode.driving;
    }

    return SpeedState(
      metersPerSecond: mps,
      movementState: MovementState.moving,
      travelMode: mode,
    );
  }
}
