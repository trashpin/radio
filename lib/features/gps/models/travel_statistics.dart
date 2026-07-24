/// Cumulative statistics for the current trip/session.
///
/// Accumulated by the GPSService as fixes arrive. Surfaced in [TravelContext]
/// and useful for a future "trip summary" and analytics. Immutable with
/// [copyWith] so each update produces a fresh snapshot.
class TravelStatistics {
  const TravelStatistics({
    this.distanceTravelledMeters = 0,
    this.maxSpeedMps = 0,
    this.parksVisited = 0,
    this.attractionsVisited = 0,
    this.tripStartedAt,
  });

  final double distanceTravelledMeters;
  final double maxSpeedMps;
  final int parksVisited;
  final int attractionsVisited;
  final DateTime? tripStartedAt;

  TravelStatistics copyWith({
    double? distanceTravelledMeters,
    double? maxSpeedMps,
    int? parksVisited,
    int? attractionsVisited,
    DateTime? tripStartedAt,
  }) {
    return TravelStatistics(
      distanceTravelledMeters:
          distanceTravelledMeters ?? this.distanceTravelledMeters,
      maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
      parksVisited: parksVisited ?? this.parksVisited,
      attractionsVisited: attractionsVisited ?? this.attractionsVisited,
      tripStartedAt: tripStartedAt ?? this.tripStartedAt,
    );
  }

  static const empty = TravelStatistics();
}
