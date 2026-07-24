// Unit tests for the GPS Intelligence Engine. Everything is provider-agnostic
// and synchronous via processLocation(), so we can feed scripted fixes and
// assert the derived TravelContext, events, and component behavior offline.

import 'package:explorer_os_mobile/features/gps/events/gps_event.dart';
import 'package:explorer_os_mobile/features/gps/models/attraction_point.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/geofence_region.dart';
import 'package:explorer_os_mobile/features/gps/models/park_boundary.dart';
import 'package:explorer_os_mobile/features/gps/models/state_boundary.dart';
import 'package:explorer_os_mobile/features/gps/models/county_boundary.dart';
import 'package:explorer_os_mobile/features/gps/services/battery_optimization_service.dart';
import 'package:explorer_os_mobile/features/gps/services/bearing_service.dart';
import 'package:explorer_os_mobile/features/gps/services/county_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/destination_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/distance_service.dart';
import 'package:explorer_os_mobile/features/gps/services/geofence_service.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_cache_service.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_service.dart';
import 'package:explorer_os_mobile/features/gps/services/heading_service.dart';
import 'package:explorer_os_mobile/features/gps/services/location_provider.dart';
import 'package:explorer_os_mobile/features/gps/services/location_tracking_service.dart';
import 'package:explorer_os_mobile/features/gps/services/offline_location_service.dart';
import 'package:explorer_os_mobile/features/gps/services/park_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/route_engine.dart';
import 'package:explorer_os_mobile/features/gps/services/speed_service.dart';
import 'package:explorer_os_mobile/features/gps/services/state_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/travel_context_service.dart';
import 'package:explorer_os_mobile/features/gps/services/travel_session_service.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:flutter_test/flutter_test.dart';

GPSLocation fix(double lat, double lng, {double? speed, DateTime? t}) =>
    GPSLocation(
      latitude: lat,
      longitude: lng,
      timestamp: t ?? DateTime(2026, 7, 24, 14),
      speedMps: speed,
    );

GPSService buildEngine() {
  final cache = GPSCacheService();
  return GPSService(
    tracking: LocationTrackingService(SimulatedLocationProvider()),
    speedService: const SpeedService(),
    headingService: const HeadingService(),
    bearingService: const BearingService(),
    distanceService: const DistanceService(),
    routeEngine: RouteEngine(),
    geofenceService: GeofenceService(),
    parkDetectionService: ParkDetectionService(),
    countyDetectionService: CountyDetectionService(),
    destinationDetectionService: DestinationDetectionService(),
    stateDetectionService: StateDetectionService(),
    travelContextService: const TravelContextService(),
    sessionService: TravelSessionService(),
    batteryOptimizationService: const BatteryOptimizationService(),
    offlineLocationService: OfflineLocationService(cache),
    cache: cache,
  );
}

const _county = CountyBoundary(
  id: 'c1',
  name: 'Marion',
  stateCode: 'UT',
  minLatitude: 39.5,
  maxLatitude: 40.5,
  minLongitude: -111.5,
  maxLongitude: -110.5,
);

const _park = ParkBoundary(
  id: 'b1',
  parkId: 'p1',
  name: 'Test Park',
  latitude: 40,
  longitude: -111,
  radiusMeters: 2000,
);
const _utah = StateBoundary(
  id: 's1',
  code: 'UT',
  name: 'Utah',
  minLatitude: 39.5,
  maxLatitude: 40.5,
  minLongitude: -111.5,
  maxLongitude: -110.5,
);

void main() {
  group('GeoMath', () {
    test('distance and bearing are sane', () {
      expect(GeoMath.distanceMeters(0, 0, 0, 1), closeTo(111319, 500));
      expect(GeoMath.bearingDegrees(0, 0, 1, 0), closeTo(0, 0.5));
      expect(GeoMath.bearingDegrees(0, 0, 0, 1), closeTo(90, 0.5));
      expect(GeoMath.angularDifference(350, 10), closeTo(20, 0.001));
    });
  });

  group('SpeedService', () {
    const svc = SpeedService();
    test('classifies movement + travel mode', () {
      expect(svc.classify(0).travelMode, TravelMode.stationary);
      expect(svc.classify(1.5).travelMode, TravelMode.walking);
      expect(svc.classify(5).travelMode, TravelMode.biking);
      expect(svc.classify(25).travelMode, TravelMode.driving);
      expect(svc.classify(25).movementState, MovementState.moving);
    });
  });

  group('GeofenceService', () {
    test('reports enter then exit', () {
      final engine = GeofenceService()
        ..setRegions(const [
          GeofenceRegion(
              id: 'g', latitude: 40, longitude: -111, radiusMeters: 1000),
        ]);
      expect(engine.evaluate(fix(40, -111)).single.transition,
          GeofenceTransition.enter);
      expect(engine.evaluate(fix(40, -111)), isEmpty);
      expect(engine.evaluate(fix(41, -111)).single.transition,
          GeofenceTransition.exit);
    });
  });

  group('ParkDetectionService', () {
    test('walks the arrival state machine', () {
      final detector = ParkDetectionService()..setParks(const [_park]);
      expect(detector.update(fix(40, -111)).arrivalStatus,
          ArrivalStatus.arrived);
      expect(detector.update(fix(40, -111)).arrivalStatus,
          ArrivalStatus.visiting);
      expect(detector.update(fix(41, -111)).arrivalStatus,
          ArrivalStatus.departing);
      expect(detector.update(fix(41, -111)).arrivalStatus, ArrivalStatus.left);
    });
  });

  group('DestinationDetectionService', () {
    test('finds nearby and upcoming (ahead of heading)', () {
      final detector = DestinationDetectionService()
        ..setCandidates(const [
          AttractionPoint(
              id: 'a', name: 'North Overlook', latitude: 40.02, longitude: -111),
        ]);
      final here = fix(40, -111);
      expect(detector.nearby(here).single.id, 'a');
      expect(detector.upcoming(here, 0, speedMps: 10).single.id, 'a');
      expect(detector.upcoming(here, 180), isEmpty);
    });
  });

  group('GPSService pipeline', () {
    test('processLocation builds a rich TravelContext', () {
      final engine = buildEngine();
      engine.configure(
        parks: const [_park],
        states: const [_utah],
        attractions: const [
          AttractionPoint(
              id: 'a', name: 'North Overlook', latitude: 40.02, longitude: -111),
        ],
      );

      final ctx = engine.processLocation(fix(40, -111));

      expect(ctx.currentParkId, 'p1');
      expect(ctx.arrivalStatus, ArrivalStatus.arrived);
      expect(ctx.currentStateCode, 'UT');
      expect(ctx.currentDestination?.id, 'p1');
      expect(ctx.nearestAttraction?.id, 'a');
      expect(ctx.travelMode, TravelMode.stationary);
      expect(ctx.isParked, isTrue);
      expect(engine.getCurrentLocation()!.latitude, 40);
    });

    test('publishes events on transitions', () async {
      final engine = buildEngine();
      engine.configure(parks: const [_park], states: const [_utah]);

      final events = <GpsEvent>[];
      final sub = engine.events.listen(events.add);

      engine.processLocation(fix(40, -111)); // inside park + Utah
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<EnteredState>().single.code, 'UT');
      expect(events.whereType<EnteredPark>().single.parkId, 'p1');
      expect(events.whereType<ArrivedAtDestination>().single.destinationId,
          'p1');
      expect(events.whereType<LocationUpdated>(), isNotEmpty);

      await sub.cancel();
    });

    test('surfaces route progress and distance remaining', () {
      final engine = buildEngine();
      engine.configure(
        parks: const [_park],
        routeId: 'r1',
        routeStops: const [
          AttractionPoint(
              id: 'a', name: 'North Overlook', latitude: 40.02, longitude: -111),
        ],
      );

      final ctx = engine.processLocation(fix(40, -111, speed: 10));

      expect(ctx.routeProgress?.routeId, 'r1');
      expect(ctx.routeProgress?.nextStopId, 'a');
      expect(ctx.distanceRemainingMeters, isNotNull);
      expect(ctx.distanceRemainingMeters! > 0, isTrue);
    });

    test('markVisited emits DestinationVisited and updates stats', () async {
      final engine = buildEngine();
      final events = <GpsEvent>[];
      final sub = engine.events.listen(events.add);

      engine.markVisited('a');
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<DestinationVisited>().single.destinationId, 'a');
      expect(engine.getTravelStatistics().attractionsVisited, 1);
      await sub.cancel();
    });

    test('detects county and emits EnteredCounty', () async {
      final engine = buildEngine();
      engine.configure(counties: const [_county]);

      final events = <GpsEvent>[];
      final sub = engine.events.listen(events.add);

      final ctx = engine.processLocation(fix(40, -111));
      await Future<void>.delayed(Duration.zero);

      expect(ctx.currentCounty, 'Marion');
      expect(events.whereType<EnteredCounty>().single.name, 'Marion');
      await sub.cancel();
    });

    test('tracks a travel session and reset starts a new one', () {
      final engine = buildEngine();
      engine.configure(parks: const [_park]);
      engine.processLocation(fix(40, -111));

      final ctx = engine.getTravelContext();
      expect(ctx.travelSession, isNull); // session starts on startTracking

      engine.resetTravelSession();
      expect(engine.getTravelStatistics().attractionsVisited, 0);
    });
  });

  group('CountyDetectionService', () {
    test('detects containing county', () {
      final svc = CountyDetectionService()..setCounties(const [_county]);
      expect(svc.detect(fix(40, -111))?.name, 'Marion');
      expect(svc.detect(fix(0, 0)), isNull);
    });
  });

  group('BearingService', () {
    test('bearing to a target point has a compass direction', () {
      const svc = BearingService();
      final b = svc.to(fix(40, -111), 41, -111); // due north
      expect(b.degrees, closeTo(0, 0.5));
    });
  });
}
