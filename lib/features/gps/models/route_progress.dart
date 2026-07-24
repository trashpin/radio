/// Progress along the user's current route/itinerary.
///
/// Produced by the RouteEngine. Captures cumulative distance travelled and,
/// when a route/itinerary is loaded, the next stop and the distance/ETA to it.
/// All fields are optional so it degrades gracefully when no route is active.
class RouteProgress {
  const RouteProgress({
    this.routeId,
    this.distanceTravelledMeters = 0,
    this.nextStopId,
    this.distanceToNextMeters,
    this.etaToNext,
    this.fractionComplete,
  });

  final String? routeId;
  final double distanceTravelledMeters;
  final String? nextStopId;
  final double? distanceToNextMeters;
  final Duration? etaToNext;

  /// 0..1 completion of the route, when computable.
  final double? fractionComplete;

  static const empty = RouteProgress();
}
