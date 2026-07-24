import 'dart:async';

import 'package:explorer_os_mobile/features/gps/models/attraction_point.dart';
import 'package:explorer_os_mobile/features/gps/models/geofence_region.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/location_snapshot.dart';
import 'package:explorer_os_mobile/features/gps/models/nearby_destination.dart';
import 'package:explorer_os_mobile/features/gps/models/park_boundary.dart';
import 'package:explorer_os_mobile/features/gps/models/state_boundary.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/models/upcoming_destination.dart';
import 'package:explorer_os_mobile/features/gps/services/destination_detector.dart';
import 'package:explorer_os_mobile/features/gps/services/geofence_engine.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_cache_service.dart';
import 'package:explorer_os_mobile/features/gps/services/heading_service.dart';
import 'package:explorer_os_mobile/features/gps/services/location_monitor.dart';
import 'package:explorer_os_mobile/features/gps/services/park_detector.dart';
import 'package:explorer_os_mobile/features/gps/services/route_engine.dart';
import 'package:explorer_os_mobile/features/gps/services/speed_service.dart';
import 'package:explorer_os_mobile/features/gps/services/travel_context_service.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// The GPS Intelligence Engine — understands WHERE the user is, WHERE they are
/// going, and turns that into a published [TravelContext].
///
/// It orchestrates every GPS sub-service: it receives fixes from the
/// [LocationMonitor], runs each one through the pipeline (speed → heading →
/// route → geofence → park → state → destinations), assembles a [TravelContext]
/// via the [TravelContextService], caches a snapshot, and re-emits the context
/// on [travelContextStream]. It holds no map-SDK dependency — positioning comes
/// from the swappable `LocationProvider` behind the monitor.
///
/// [processLocation] is deliberately synchronous and side-effect-contained so
/// the entire engine can be driven and asserted in tests without timers.
class GPSService {
  GPSService({
    required this.monitor,
    required this.speedService,
    required this.headingService,
    required this.routeEngine,
    required this.geofenceEngine,
    required this.parkDetector,
    required this.destinationDetector,
    required this.travelContextService,
    required this.cache,
  });

  final LocationMonitor monitor;
  final SpeedService speedService;
  final HeadingService headingService;
  final RouteEngine routeEngine;
  final GeofenceEngine geofenceEngine;
  final ParkDetector parkDetector;
  final DestinationDetector destinationDetector;
  final TravelContextService travelContextService;
  final GPSCacheService cache;

  final StreamController<TravelContext> _contextController =
      StreamController<TravelContext>.broadcast();
  Stream<TravelContext> get travelContextStream => _contextController.stream;

  GpsTrackingStatus _status = GpsTrackingStatus.idle;
  GpsTrackingStatus get status => _status;

  TravelContext _current = TravelContext.initial();
  GPSLocation? _previous;
  List<StateBoundary> _states = const [];

  /// Seeds the engine with the content it reasons about (from repositories).
  /// Geofences default to circles derived from park boundaries.
  void configure({
    List<ParkBoundary> parks = const [],
    List<StateBoundary> states = const [],
    List<AttractionPoint> attractions = const [],
    List<GeofenceRegion> geofences = const [],
    String? routeId,
    List<AttractionPoint> routeStops = const [],
  }) {
    parkDetector.setParks(parks);
    _states = states;
    destinationDetector.setCandidates(attractions);
    geofenceEngine.setRegions(
      geofences.isNotEmpty ? geofences : _geofencesFromParks(parks),
    );
    routeEngine.setRoute(routeId: routeId, stops: routeStops);
  }

  // --- Tracking lifecycle --------------------------------------------------

  Future<void> startTracking() async {
    if (_status == GpsTrackingStatus.tracking) return;
    _status = GpsTrackingStatus.tracking;
    await monitor.start(processLocation);
  }

  Future<void> stopTracking() async {
    _status = GpsTrackingStatus.stopped;
    await monitor.stop();
  }

  void pauseTracking() {
    if (_status != GpsTrackingStatus.tracking) return;
    _status = GpsTrackingStatus.paused;
    monitor.pause();
  }

  void resumeTracking() {
    if (_status != GpsTrackingStatus.paused) return;
    _status = GpsTrackingStatus.tracking;
    monitor.resume();
  }

  // --- The pipeline --------------------------------------------------------

  /// Runs one fix through the full pipeline, updates + emits the context, and
  /// returns it. Called for every fix (and directly in tests).
  TravelContext processLocation(GPSLocation loc) {
    final mps = loc.speedMps ?? _derivedSpeedMps(loc);
    final speed = speedService.classify(mps);
    final heading = headingService.resolve(loc, previous: _previous);

    routeEngine.onLocation(loc);
    geofenceEngine.evaluate(loc); // transitions available for future triggers
    final park = parkDetector.update(loc);
    final state = _detectState(loc);

    final nearby = destinationDetector.nearby(loc);
    final upcoming = heading == null
        ? const <UpcomingDestination>[]
        : destinationDetector.upcoming(loc, heading.degrees,
            speedMps: speed.metersPerSecond);
    final NearbyDestination? nearest = nearby.isEmpty ? null : nearby.first;
    final UpcomingDestination? next = upcoming.isEmpty ? null : upcoming.first;

    final isParked =
        speed.travelMode == TravelMode.stationary && park.parkId != null;

    final context = travelContextService.build(
      now: loc.timestamp,
      location: loc,
      stateCode: state?.code,
      stateName: state?.name,
      parkId: park.parkId,
      arrivalState: park.arrivalState,
      heading: heading,
      speed: speed,
      isParked: isParked,
      distanceTravelledMeters: routeEngine.distanceTravelledMeters,
      nearest: nearest,
      next: next,
      estimatedArrival: next?.eta,
      nearby: nearby,
      upcoming: upcoming,
      visited: destinationDetector.visited,
    );

    _current = context;
    _previous = loc;
    cache.record(LocationSnapshot(
      location: loc,
      movementState: speed.movementState,
      stateCode: state?.code,
      parkId: park.parkId,
    ));
    _contextController.add(context);
    return context;
  }

  // --- Public query API ----------------------------------------------------

  GPSLocation? getCurrentLocation() => monitor.last ?? cache.last?.location;

  TravelContext getTravelContext() => _current;

  List<UpcomingDestination> getUpcomingDestinations() =>
      _current.upcomingDestinations;

  List<NearbyDestination> getNearbyDestinations() =>
      _current.nearbyDestinations;

  /// Bearing (0–360°) from one fix to another.
  double calculateHeading(GPSLocation from, GPSLocation to) =>
      headingService.bearingBetween(from, to);

  /// Great-circle distance (meters) between two fixes.
  double calculateDistance(GPSLocation a, GPSLocation b) =>
      GeoMath.distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude);

  bool isMoving() => _current.isMoving;

  bool isApproachingDestination() =>
      _current.arrivalState == ArrivalState.approaching;

  bool isLeavingDestination() =>
      _current.arrivalState == ArrivalState.departing ||
      _current.arrivalState == ArrivalState.left;

  void markVisited(String attractionId) =>
      destinationDetector.markVisited(attractionId);

  void dispose() => _contextController.close();

  // --- Internals -----------------------------------------------------------

  double _derivedSpeedMps(GPSLocation loc) {
    final prev = _previous;
    if (prev == null) return 0;
    final meters = GeoMath.distanceMeters(
        prev.latitude, prev.longitude, loc.latitude, loc.longitude);
    final seconds =
        loc.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
    return seconds > 0 ? meters / seconds : 0;
  }

  StateBoundary? _detectState(GPSLocation loc) {
    for (final state in _states) {
      if (state.contains(loc.latitude, loc.longitude)) return state;
    }
    return null;
  }

  List<GeofenceRegion> _geofencesFromParks(List<ParkBoundary> parks) {
    return parks
        .map((p) => GeofenceRegion(
              id: 'park_${p.parkId}',
              latitude: p.latitude,
              longitude: p.longitude,
              radiusMeters: p.radiusMeters,
              type: GeofenceType.park,
              referenceId: p.parkId,
            ))
        .toList(growable: false);
  }
}
