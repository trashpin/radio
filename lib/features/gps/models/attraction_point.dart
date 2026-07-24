/// A lightweight known point of interest fed INTO the engine (its coordinates
/// are fixed; distance/bearing are computed per-fix into
/// [NearbyDestination]/[UpcomingDestination]).
///
/// Used to seed the DestinationDetector and RouteEngine from backend content
/// (e.g. stops) without coupling them to a specific content model.
class AttractionPoint {
  const AttractionPoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.parkId,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? parkId;
}
