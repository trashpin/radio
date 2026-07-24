import 'dart:async';

import 'package:explorer_os_mobile/features/gps/events/gps_event.dart';
import 'package:explorer_os_mobile/features/gps/models/attraction_point.dart';
import 'package:explorer_os_mobile/features/gps/models/county_boundary.dart';
import 'package:explorer_os_mobile/features/gps/models/current_destination.dart';
import 'package:explorer_os_mobile/features/gps/models/geofence_region.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/location_snapshot.dart';
import 'package:explorer_os_mobile/features/gps/models/nearby_destination.dart';
import 'package:explorer_os_mobile/features/gps/models/park_boundary.dart';
import 'package:explorer_os_mobile/features/gps/models/speed_state.dart';
import 'package:explorer_os_mobile/features/gps/models/state_boundary.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_statistics.dart';
import 'package:explorer_os_mobile/features/gps/models/upcoming_destination.dart';
import 'package:explorer_os_mobile/features/gps/services/battery_optimization_service.dart';
import 'package:explorer_os_mobile/features/gps/services/bearing_service.dart';
import 'package:explorer_os_mobile/features/gps/services/county_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/destination_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/distance_service.dart';
import 'package:explorer_os_mobile/features/gps/services/geofence_service.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_cache_service.dart';
import 'package:explorer_os_mobile/features/gps/services/heading_service.dart';
import 'package:explorer_os_mobile/features/gps/services/location_tracking_service.dart';
import 'package:explorer_os_mobile/features/gps/services/offline_location_service.dart';
import 'package:explorer_os_mobile/features/gps/services/park_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/route_engine.dart';
import 'package:explorer_os_mobile/features/gps/services/speed_service.dart';
import 'package:explorer_os_mobile/features/gps/services/state_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/travel_context_service.dart';
import 'package:explorer_os_mobile/features/gps/services/travel_session_service.dart';

/// The GPS Intelligence Engine — understands WHERE the user is, WHERE they are
/// going, what they've visited, and publishes a [TravelContext] plus a stream of
/// [GpsEvent]s the rest of ExplorerOS reacts to.
///
/// It orchestrates every GPS sub-service: fixes arrive from the
/// [LocationTrackingService]; each runs through the pipeline (speed → heading →
/// distance/route → geofence → park → county → state → destinations); a
/// [TravelContext] is assembled + cached; the session updates; and meaningful
/// changes are emitted as events. No map-SDK dependency — positioning comes from
/// the swappable `LocationProvider`.
///
/// [processLocation] is synchronous and side-effect-contained so the whole
/// engine is drivable/assertable in tests without timers.
class GPSService {
  GPSService({
    required this.tracking,
    required this.speedService,
    required this.headingService,
    required this.bearingService,
    required this.distanceService,
    required this.routeEngine,
    required this.geofenceService,
    required this.parkDetectionService,
    required this.countyDetectionService,
    required this.destinationDetectionService,
    required this.stateDetectionService,
    required this.travelContextService,
    required this.sessionService,
    required this.batteryOptimizationService,
    required this.offlineLocationService,
    required this.cache,
  });

  final LocationTrackingService tracking;
  final SpeedService speedService;
  final HeadingService headingService;
  final BearingService bearingService;
  final DistanceService distanceService;
  final RouteEngine routeEngine;
  final GeofenceService geofenceService;
  final ParkDetectionService parkDetectionService;
  final CountyDetectionService countyDetectionService;
  final DestinationDetectionService destinationDetectionService;
  final StateDetectionService stateDetectionService;
  final TravelContextService travelContextService;
  final TravelSessionService sessionService;
  final BatteryOptimizationService batteryOptimizationService;
  final OfflineLocationService offlineLocationService;
  final GPSCacheService cache;

  final StreamController<TravelContext> _contextController =
      StreamController<TravelContext>.broadcast();
  final StreamController<GpsEvent> _eventController =
      StreamController<GpsEvent>.broadcast();

  Stream<TravelContext> get travelContextStream => _contextController.stream;
  Stream<GpsEvent> get events => _eventController.stream;

  GpsTrackingStatus _status = GpsTrackingStatus.idle;
  GpsTrackingStatus get status => _status;

  TravelContext _current = TravelContext.initial();
  TravelStatistics _stats = TravelStatistics.empty;
  GPSLocation? _previous;
  bool _gpsLost = false;

  // Transition trackers.
  String? _prevStateCode;
  String? _prevStateName;
  String? _prevCountyId;
  String? _prevCountyName;
  String? _prevParkId;
  ArrivalStatus? _prevArrival;
  MovementState? _prevMovement;
  TravelMode? _prevTravelMode;
  CardinalDirection? _prevHeadingDirection;
  bool _wasMoving = false;
  final Set<String> _seenNearby = {};

  /// Seeds the engine with content it reasons about (from repositories).
  void configure({
    List<ParkBoundary> parks = const [],
    List<StateBoundary> states = const [],
    List<CountyBoundary> counties = const [],
    List<AttractionPoint> attractions = const [],
    List<GeofenceRegion> geofences = const [],
    String? routeId,
    List<AttractionPoint> routeStops = const [],
  }) {
    parkDetectionService.setParks(parks);
    stateDetectionService.setStates(states);
    countyDetectionService.setCounties(counties);
    destinationDetectionService.setCandidates(attractions);
    geofenceService.setRegions(
      geofences.isNotEmpty ? geofences : _geofencesFromParks(parks),
    );
    routeEngine.setRoute(routeId: routeId, stops: routeStops);
  }

  // --- Tracking lifecycle --------------------------------------------------

  Future<void> startTracking() async {
    if (_status == GpsTrackingStatus.tracking) return;
    _status = GpsTrackingStatus.tracking;
    sessionService.start();
    _stats = TravelStatistics(tripStartedAt: DateTime.now());
    await tracking.start(processLocation);
  }

  Future<void> stopTracking() async {
    _status = GpsTrackingStatus.stopped;
    sessionService.stop();
    await tracking.stop();
    _emit(TravelStopped(DateTime.now()));
  }

  void pauseTracking() {
    if (_status != GpsTrackingStatus.tracking) return;
    _status = GpsTrackingStatus.paused;
    tracking.pause();
  }

  void resumeTracking() {
    if (_status != GpsTrackingStatus.paused) return;
    _status = GpsTrackingStatus.tracking;
    tracking.resume();
  }

  /// Starts tracking optimized for a backgrounded app (emits a background event
  /// so systems like Explorer Radio know to keep running).
  Future<void> startBackgroundTracking() async {
    _emit(BackgroundTrackingStarted(DateTime.now()));
    await startTracking();
  }

  Future<void> stopBackgroundTracking() async {
    _emit(BackgroundTrackingStopped(DateTime.now()));
    await stopTracking();
  }

  /// Ends the current trip and starts a fresh one (stats reset).
  void resetTravelSession() {
    sessionService.reset();
    _stats = TravelStatistics(tripStartedAt: DateTime.now());
    routeEngine.reset();
    _seenNearby.clear();
    _emit(TravelStarted(DateTime.now()));
  }

  /// Signal that positioning was lost (called by a real provider adapter).
  void reportSignalLost() {
    if (_gpsLost) return;
    _gpsLost = true;
    _emit(GpsLost(DateTime.now()));
  }

  /// The battery-aware sampling policy for the current movement/mode.
  LocationSamplingPolicy recommendedSamplingPolicy() =>
      batteryOptimizationService.recommend(
        _current.movementState,
        _current.travelMode,
      );

  // --- The pipeline --------------------------------------------------------

  TravelContext processLocation(GPSLocation loc) {
    if (_gpsLost) {
      _gpsLost = false;
      _emit(GpsRecovered(loc.timestamp));
    }

    final mps = loc.speedMps ?? _derivedSpeedMps(loc);
    final speed = speedService.classify(mps);
    final heading = headingService.resolve(loc, previous: _previous);

    routeEngine.onLocation(loc);
    geofenceService.evaluate(loc);
    final park = parkDetectionService.update(loc);
    final county = countyDetectionService.detect(loc);
    final state = stateDetectionService.detect(loc);
    final routeProgress = routeEngine.progress(
      loc,
      speedMps: speed.metersPerSecond,
      visited: destinationDetectionService.visited.toSet(),
    );

    final nearby = destinationDetectionService.nearby(loc);
    final upcoming = heading == null
        ? const <UpcomingDestination>[]
        : destinationDetectionService.upcoming(loc, heading.degrees,
            speedMps: speed.metersPerSecond);
    final NearbyDestination? nearest = nearby.isEmpty ? null : nearby.first;
    final UpcomingDestination? next = upcoming.isEmpty ? null : upcoming.first;

    final isParked =
        speed.travelMode == TravelMode.stationary && park.parkId != null;

    _stats = _stats.copyWith(
      distanceTravelledMeters: routeEngine.distanceTravelledMeters,
      maxSpeedMps: mps > _stats.maxSpeedMps ? mps : _stats.maxSpeedMps,
    );

    final currentDestination = park.parkId == null
        ? null
        : CurrentDestination(
            id: park.parkId!,
            arrivalStatus: park.arrivalStatus,
            parkId: park.parkId,
          );

    final context = travelContextService.build(
      now: loc.timestamp,
      location: loc,
      stateCode: state?.code,
      stateName: state?.name,
      countyName: county?.name,
      parkId: park.parkId,
      currentDestination: currentDestination,
      arrivalStatus: park.arrivalStatus,
      heading: heading,
      bearingDegrees: heading?.degrees,
      speed: speed,
      isParked: isParked,
      distanceTravelledMeters: routeEngine.distanceTravelledMeters,
      nearest: nearest,
      next: next,
      estimatedArrival: next?.eta,
      nearby: nearby,
      upcoming: upcoming,
      visited: destinationDetectionService.visited,
      routeProgress: routeProgress,
      distanceRemainingMeters:
          routeProgress.distanceToNextMeters ?? next?.distanceMeters,
      statistics: _stats,
      travelSession: sessionService.current,
    );

    _publishTransitions(context, speed, heading?.direction, state?.name,
        county, nearby);

    sessionService.recordFix(_stats);
    _current = context;
    _previous = loc;
    cache.record(LocationSnapshot(
      location: loc,
      movementState: speed.movementState,
      stateCode: state?.code,
      parkId: park.parkId,
    ));
    _contextController.add(context);
    _emit(LocationUpdated(loc.timestamp, loc));
    return context;
  }

  // --- Public query API ----------------------------------------------------

  GPSLocation? getCurrentLocation() =>
      tracking.last ?? offlineLocationService.lastKnownLocation();

  TravelContext getTravelContext() => _current;
  TravelStatistics getTravelStatistics() => _stats;

  List<UpcomingDestination> getUpcomingDestinations() =>
      _current.upcomingDestinations;
  List<NearbyDestination> getNearbyDestinations() =>
      _current.nearbyDestinations;

  double calculateHeading(GPSLocation from, GPSLocation to) =>
      headingService.bearingBetween(from, to);

  double calculateBearing(GPSLocation from, GPSLocation to) =>
      bearingService.between(from, to).degrees;

  double calculateDistance(GPSLocation a, GPSLocation b) =>
      distanceService.between(a, b);

  Duration? calculateETA(double distanceMeters, double? speedMps) =>
      distanceService.eta(distanceMeters, speedMps);

  /// The current compass travel direction, if a heading is known.
  CardinalDirection? calculateTravelDirection() => _current.heading?.direction;

  bool isMoving() => _current.isMoving;
  bool isStopped() => !_current.isMoving;

  bool isApproachingDestination() =>
      _current.arrivalStatus == ArrivalStatus.approaching;

  bool isLeavingDestination() =>
      _current.arrivalStatus == ArrivalStatus.departing ||
      _current.arrivalStatus == ArrivalStatus.left;

  void markVisited(String attractionId) {
    if (destinationDetectionService.isVisited(attractionId)) return;
    destinationDetectionService.markVisited(attractionId);
    _stats = _stats.copyWith(
      attractionsVisited: _stats.attractionsVisited + 1,
    );
    _emit(DestinationVisited(DateTime.now(), attractionId));
  }

  void notifyRouteChanged() => _emit(RouteChanged(DateTime.now()));

  void dispose() {
    _contextController.close();
    _eventController.close();
  }

  // --- Internals -----------------------------------------------------------

  void _emit(GpsEvent event) => _eventController.add(event);

  void _publishTransitions(
    TravelContext ctx,
    SpeedState speed,
    CardinalDirection? headingDirection,
    String? stateName,
    CountyBoundary? county,
    List<NearbyDestination> nearby,
  ) {
    // State enter/exit.
    if (ctx.currentStateCode != _prevStateCode) {
      if (_prevStateCode != null) {
        _emit(ExitedState(ctx.timestamp, _prevStateCode!, _prevStateName ?? ''));
      }
      if (ctx.currentStateCode != null) {
        _emit(EnteredState(
            ctx.timestamp, ctx.currentStateCode!, stateName ?? ''));
      }
      _prevStateCode = ctx.currentStateCode;
      _prevStateName = stateName;
    }

    // County enter/exit.
    final countyId = county?.id;
    if (countyId != _prevCountyId) {
      if (_prevCountyId != null) {
        _emit(ExitedCounty(ctx.timestamp, _prevCountyId!, _prevCountyName ?? ''));
      }
      if (countyId != null) {
        _emit(EnteredCounty(ctx.timestamp, countyId, county?.name ?? ''));
      }
      _prevCountyId = countyId;
      _prevCountyName = county?.name;
    }

    // Park enter/exit.
    if (ctx.currentParkId != _prevParkId) {
      if (_prevParkId != null) {
        _emit(ExitedPark(ctx.timestamp, _prevParkId!));
      }
      if (ctx.currentParkId != null) {
        _emit(EnteredPark(ctx.timestamp, ctx.currentParkId!));
        _stats = _stats.copyWith(parksVisited: _stats.parksVisited + 1);
      }
      _prevParkId = ctx.currentParkId;
    }

    // Arrival status transitions.
    if (ctx.arrivalStatus != _prevArrival && ctx.currentParkId != null) {
      final id = ctx.currentParkId!;
      switch (ctx.arrivalStatus) {
        case ArrivalStatus.approaching:
          _emit(ApproachingDestination(ctx.timestamp, id));
        case ArrivalStatus.arrived:
          _emit(ArrivedAtDestination(ctx.timestamp, id));
        case ArrivalStatus.visiting:
          _emit(VisitingDestination(ctx.timestamp, id));
        case ArrivalStatus.departing:
          _emit(LeavingDestination(ctx.timestamp, id));
        case ArrivalStatus.left:
        case null:
          break;
      }
    }
    _prevArrival = ctx.arrivalStatus;

    // Speed / travel-mode change.
    if (speed.movementState != _prevMovement ||
        speed.travelMode != _prevTravelMode) {
      _emit(SpeedChanged(ctx.timestamp, speed));
      _prevMovement = speed.movementState;
      _prevTravelMode = speed.travelMode;
    }

    // Heading change (by compass point).
    if (headingDirection != null && headingDirection != _prevHeadingDirection) {
      _emit(HeadingChanged(ctx.timestamp, ctx.bearingDegrees ?? 0));
      _prevHeadingDirection = headingDirection;
    }

    // New nearby destinations.
    for (final n in nearby) {
      if (_seenNearby.add(n.id)) {
        _emit(NearbyDestinationDetected(ctx.timestamp, n.id));
      }
    }

    // Travel started / stopped.
    final isMovingNow = speed.isMoving;
    if (isMovingNow && !_wasMoving) {
      _emit(TravelStarted(ctx.timestamp));
    } else if (!isMovingNow && _wasMoving) {
      _emit(TravelStopped(ctx.timestamp));
    }
    _wasMoving = isMovingNow;
  }

  double _derivedSpeedMps(GPSLocation loc) {
    final prev = _previous;
    if (prev == null) return 0;
    final meters = distanceService.between(prev, loc);
    final seconds =
        loc.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
    return seconds > 0 ? meters / seconds : 0;
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
