/// A driving (road-network) distance + ETA between two points, from Google's
/// Distance Matrix API — as opposed to the straight-line ("as the crow
/// flies") distance [GeoMath.distanceMeters] computes everywhere else.
///
/// Kept deliberately separate from [NearbyGemHit]/[NearbyDestination] etc: the
/// straight-line distance is cheap, synchronous, and always available (used
/// for radius filtering + ranking); this is fetched asynchronously, over the
/// network, only for the small set of items actually shown, and may never
/// arrive (no signal, API quota, key not configured for Distance Matrix).
class DrivingDistanceResult {
  const DrivingDistanceResult({
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final double distanceMeters;
  final int durationSeconds;

  double get miles => distanceMeters / 1609.344;
  Duration get duration => Duration(seconds: durationSeconds);
}
