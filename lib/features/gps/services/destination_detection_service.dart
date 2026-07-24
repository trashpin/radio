import 'package:explorer_os_mobile/features/gps/models/attraction_point.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/nearby_destination.dart';
import 'package:explorer_os_mobile/features/gps/models/upcoming_destination.dart';
import 'package:explorer_os_mobile/features/gps/services/nearby_destination_service.dart';
import 'package:explorer_os_mobile/features/gps/services/upcoming_destination_service.dart';

/// Coordinates destination detection: holds the candidate attractions + visited
/// set, and delegates the actual spatial math to [NearbySearchService] and
/// [UpcomingDestinationService].
///
/// WHY THIS EXISTS: it owns the STATE (candidates + visited) while the two
/// search services own the STATELESS math — so the "nearby" and "upcoming"
/// algorithms live in exactly one place each and can also be used directly by
/// the Explorer/Map screens. This service is what the engine talks to.
class DestinationDetectionService {
  DestinationDetectionService({
    this.nearbySearch = const NearbyDestinationService(),
    this.upcomingSearch = const UpcomingDestinationService(),
  });

  final NearbyDestinationService nearbySearch;
  final UpcomingDestinationService upcomingSearch;

  final List<AttractionPoint> _candidates = [];
  final Set<String> _visited = {};

  void setCandidates(List<AttractionPoint> candidates) {
    _candidates
      ..clear()
      ..addAll(candidates);
  }

  List<String> get visited => List.unmodifiable(_visited);
  bool isVisited(String id) => _visited.contains(id);
  void markVisited(String id) => _visited.add(id);

  List<NearbyDestination> nearby(
    GPSLocation loc, {
    double radiusMeters = 5000,
    int limit = 10,
  }) =>
      nearbySearch.search(_candidates, loc,
          radiusMeters: radiusMeters, limit: limit);

  List<UpcomingDestination> upcoming(
    GPSLocation loc,
    double headingDegrees, {
    double coneDegrees = 60,
    double radiusMeters = 20000,
    double? speedMps,
    int limit = 5,
  }) =>
      upcomingSearch.search(
        _candidates,
        loc,
        headingDegrees,
        visited: _visited,
        coneDegrees: coneDegrees,
        radiusMeters: radiusMeters,
        speedMps: speedMps,
        limit: limit,
      );
}
