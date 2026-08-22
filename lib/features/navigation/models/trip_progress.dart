import 'package:explorer_os_mobile/features/navigation/models/route_plan.dart';

/// Where a tracked trip currently stands relative to its [RoutePlan].
enum TripStatus { idle, onRoute, offRoute, recalculating, arrived, cancelled }

/// A live snapshot of trip progress — recomputed on every GPS fix by
/// `TripTracker`. Carries only derived numbers; the route/step data itself
/// stays on the tracker's current `RoutePlan`.
class TripProgress {
  const TripProgress({
    this.status = TripStatus.idle,
    this.destinationName,
    this.currentStepIndex = 0,
    this.distanceToManeuverMeters,
    this.offRouteMeters = 0,
    this.distanceRemainingMeters,
  });

  final TripStatus status;
  final String? destinationName;
  final int currentStepIndex;
  final double? distanceToManeuverMeters;
  final double offRouteMeters;
  final double? distanceRemainingMeters;

  bool get isActive =>
      status == TripStatus.onRoute ||
      status == TripStatus.offRoute ||
      status == TripStatus.recalculating;

  TripProgress copyWith({
    TripStatus? status,
    String? destinationName,
    int? currentStepIndex,
    double? distanceToManeuverMeters,
    double? offRouteMeters,
    double? distanceRemainingMeters,
  }) =>
      TripProgress(
        status: status ?? this.status,
        destinationName: destinationName ?? this.destinationName,
        currentStepIndex: currentStepIndex ?? this.currentStepIndex,
        distanceToManeuverMeters:
            distanceToManeuverMeters ?? this.distanceToManeuverMeters,
        offRouteMeters: offRouteMeters ?? this.offRouteMeters,
        distanceRemainingMeters:
            distanceRemainingMeters ?? this.distanceRemainingMeters,
      );

  static const idleState = TripProgress();
}

/// One notable thing that happened as a trip progressed — what `TripTracker`
/// emits on its event stream for the Copilot Brain to react to. Deliberately
/// carries the route's own step/instruction text (Google's own wording) so
/// nothing downstream ever has to invent or paraphrase a safety-relevant
/// instruction.
sealed class TripEvent {
  const TripEvent();
}

class TripStarted extends TripEvent {
  const TripStarted(this.destinationName);
  final String? destinationName;
}

class ApproachingManeuver extends TripEvent {
  const ApproachingManeuver(this.step, this.distanceMeters);
  final RouteStep step;
  final double distanceMeters;
}

class MissedTurn extends TripEvent {
  const MissedTurn();
}

class Recalculating extends TripEvent {
  const Recalculating();
}

class TripArrived extends TripEvent {
  const TripArrived();
}

class TripEnded extends TripEvent {
  const TripEnded();
}
