/// Estimates arrival time from a distance and a speed.
///
/// WHY THIS EXISTS: ETA is a distinct, reusable calculation the engine, route
/// progress, and upcoming-destination logic all care about. Isolating it here
/// (rather than mixing it into DistanceService) gives one canonical, injectable
/// place to evolve the estimate later (e.g. factoring in speed limits, traffic,
/// or terrain) without touching callers.
class ETAService {
  const ETAService();

  /// ETA for [distanceMeters] at [speedMps]; null when not moving (speed <= 0),
  /// since an ETA would be meaningless.
  Duration? estimate(double distanceMeters, double? speedMps) {
    if (speedMps == null || speedMps <= 0) return null;
    return Duration(seconds: (distanceMeters / speedMps).round());
  }
}
