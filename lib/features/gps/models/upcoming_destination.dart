/// A point of interest that lies AHEAD along the user's direction of travel.
///
/// Produced by the DestinationDetector by filtering candidates to those within
/// a cone of the current heading. Adds an [eta] estimate (from distance and
/// current speed) on top of the nearby fields. This is the primary signal the
/// AI Producer uses to pre-load "upcoming attraction" audio (GPS-ready).
class UpcomingDestination {
  const UpcomingDestination({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.bearingDegrees,
    this.eta,
    this.parkId,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final double bearingDegrees;

  /// Estimated time to arrival, when a speed is known.
  final Duration? eta;
  final String? parkId;
}
