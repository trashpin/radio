/// A known point of interest that is currently near the user.
///
/// Produced by the DestinationDetector. Wraps a content reference (id/name +
/// coordinates) with the computed [distanceMeters] and [bearingDegrees] from the
/// user's current position, so the UI/Producer can rank and describe it.
class NearbyDestination {
  const NearbyDestination({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.bearingDegrees,
    this.parkId,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final double bearingDegrees;
  final String? parkId;
}
