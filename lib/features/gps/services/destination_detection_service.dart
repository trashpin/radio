import 'package:explorer_os_mobile/features/gps/models/attraction_point.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/nearby_destination.dart';
import 'package:explorer_os_mobile/features/gps/models/upcoming_destination.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Computes which known attractions are NEARBY and which are UPCOMING (ahead
/// along the heading), and tracks which have been visited.
///
/// WHY THIS EXISTS: this is the spatial reasoning that turns a raw position into
/// "there are 3 attractions near you; the next one on your route is 800 m
/// ahead." The Producer relies on "upcoming" to pre-load location audio, and
/// visited-tracking drives DestinationVisited events.
class DestinationDetectionService {
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

  /// Attractions within [radiusMeters], nearest first.
  List<NearbyDestination> nearby(
    GPSLocation loc, {
    double radiusMeters = 5000,
    int limit = 10,
  }) {
    final results = <NearbyDestination>[];
    for (final c in _candidates) {
      final distance = GeoMath.distanceMeters(
          loc.latitude, loc.longitude, c.latitude, c.longitude);
      if (distance > radiusMeters) continue;
      results.add(NearbyDestination(
        id: c.id,
        name: c.name,
        latitude: c.latitude,
        longitude: c.longitude,
        distanceMeters: distance,
        bearingDegrees: GeoMath.bearingDegrees(
            loc.latitude, loc.longitude, c.latitude, c.longitude),
        parkId: c.parkId,
      ));
    }
    results.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return results.take(limit).toList(growable: false);
  }

  /// Attractions AHEAD of the user (within [coneDegrees] of [headingDegrees]),
  /// nearest first, with an ETA when a speed is provided.
  List<UpcomingDestination> upcoming(
    GPSLocation loc,
    double headingDegrees, {
    double coneDegrees = 60,
    double radiusMeters = 20000,
    double? speedMps,
    int limit = 5,
  }) {
    final results = <UpcomingDestination>[];
    for (final c in _candidates) {
      if (_visited.contains(c.id)) continue;
      final distance = GeoMath.distanceMeters(
          loc.latitude, loc.longitude, c.latitude, c.longitude);
      if (distance > radiusMeters) continue;
      final bearing = GeoMath.bearingDegrees(
          loc.latitude, loc.longitude, c.latitude, c.longitude);
      if (GeoMath.angularDifference(headingDegrees, bearing) > coneDegrees) {
        continue;
      }
      results.add(UpcomingDestination(
        id: c.id,
        name: c.name,
        latitude: c.latitude,
        longitude: c.longitude,
        distanceMeters: distance,
        bearingDegrees: bearing,
        eta: (speedMps != null && speedMps > 0)
            ? Duration(seconds: (distance / speedMps).round())
            : null,
        parkId: c.parkId,
      ));
    }
    results.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return results.take(limit).toList(growable: false);
  }
}
