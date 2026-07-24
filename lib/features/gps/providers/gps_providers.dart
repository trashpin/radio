import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/services/battery_optimization_service.dart';
import 'package:explorer_os_mobile/features/gps/services/bearing_service.dart';
import 'package:explorer_os_mobile/features/gps/services/county_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/destination_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/distance_service.dart';
import 'package:explorer_os_mobile/features/gps/services/eta_service.dart';
import 'package:explorer_os_mobile/features/gps/services/geofence_service.dart';
import 'package:explorer_os_mobile/features/gps/services/geolocator_location_provider.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_cache_service.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_service.dart';
import 'package:explorer_os_mobile/features/gps/services/heading_service.dart';
import 'package:explorer_os_mobile/features/gps/services/location_provider.dart';
import 'package:explorer_os_mobile/features/gps/services/location_tracking_service.dart';
import 'package:explorer_os_mobile/features/gps/services/nearby_destination_service.dart';
import 'package:explorer_os_mobile/features/gps/services/offline_location_service.dart';
import 'package:explorer_os_mobile/features/gps/services/park_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/route_engine.dart';
import 'package:explorer_os_mobile/features/gps/services/speed_service.dart';
import 'package:explorer_os_mobile/features/gps/services/state_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/travel_context_service.dart';
import 'package:explorer_os_mobile/features/gps/services/travel_session_service.dart';
import 'package:explorer_os_mobile/features/gps/services/upcoming_destination_service.dart';

/// Dependency-injection wiring for the GPS Intelligence Engine.
///
/// Every sub-service is a scope singleton so they share state across a fix
/// (route distance, park/county/geofence membership, session). The default
/// [locationProviderProvider] is a [SimulatedLocationProvider] — override it in
/// `main`/tests with a real provider (system/Google/Apple/offline/background).

/// The active positioning source. Defaults to the real device provider
/// ([GeolocatorLocationProvider]); override with a [SimulatedLocationProvider]
/// (tests) or a future Google/Apple/offline provider without touching the
/// engine. Constructing it does not prompt for permission — that happens lazily
/// on `startTracking()`.
final locationProviderProvider = Provider<LocationProvider>((ref) {
  final provider = GeolocatorLocationProvider();
  ref.onDispose(provider.dispose);
  return provider;
});

final speedServiceProvider =
    Provider<SpeedService>((ref) => const SpeedService());
final headingServiceProvider =
    Provider<HeadingService>((ref) => const HeadingService());
final bearingServiceProvider =
    Provider<BearingService>((ref) => const BearingService());
final distanceServiceProvider =
    Provider<DistanceService>((ref) => const DistanceService());
final etaServiceProvider = Provider<ETAService>((ref) => const ETAService());
final routeEngineProvider = Provider<RouteEngine>((ref) => RouteEngine());
final geofenceServiceProvider =
    Provider<GeofenceService>((ref) => GeofenceService());
final parkDetectionServiceProvider =
    Provider<ParkDetectionService>((ref) => ParkDetectionService());
final countyDetectionServiceProvider =
    Provider<CountyDetectionService>((ref) => CountyDetectionService());
final stateDetectionServiceProvider =
    Provider<StateDetectionService>((ref) => StateDetectionService());
final nearbyDestinationServiceProvider =
    Provider<NearbyDestinationService>(
        (ref) => const NearbyDestinationService());
final upcomingDestinationServiceProvider =
    Provider<UpcomingDestinationService>(
        (ref) => const UpcomingDestinationService());
final destinationDetectionServiceProvider =
    Provider<DestinationDetectionService>((ref) {
  return DestinationDetectionService(
    nearbySearch: ref.watch(nearbyDestinationServiceProvider),
    upcomingSearch: ref.watch(upcomingDestinationServiceProvider),
  );
});
final travelContextServiceProvider =
    Provider<TravelContextService>((ref) => const TravelContextService());
final travelSessionServiceProvider =
    Provider<TravelSessionService>((ref) => TravelSessionService());
final batteryOptimizationServiceProvider =
    Provider<BatteryOptimizationService>(
        (ref) => const BatteryOptimizationService());
final gpsCacheServiceProvider =
    Provider<GPSCacheService>((ref) => GPSCacheService());
final offlineLocationServiceProvider = Provider<OfflineLocationService>(
  (ref) => OfflineLocationService(ref.watch(gpsCacheServiceProvider)),
);
final locationTrackingServiceProvider = Provider<LocationTrackingService>(
  (ref) => LocationTrackingService(ref.watch(locationProviderProvider)),
);

/// The composed GPS Intelligence Engine.
final gpsServiceProvider = Provider<GPSService>((ref) {
  final service = GPSService(
    tracking: ref.watch(locationTrackingServiceProvider),
    speedService: ref.watch(speedServiceProvider),
    headingService: ref.watch(headingServiceProvider),
    bearingService: ref.watch(bearingServiceProvider),
    distanceService: ref.watch(distanceServiceProvider),
    etaService: ref.watch(etaServiceProvider),
    routeEngine: ref.watch(routeEngineProvider),
    geofenceService: ref.watch(geofenceServiceProvider),
    parkDetectionService: ref.watch(parkDetectionServiceProvider),
    countyDetectionService: ref.watch(countyDetectionServiceProvider),
    destinationDetectionService:
        ref.watch(destinationDetectionServiceProvider),
    stateDetectionService: ref.watch(stateDetectionServiceProvider),
    travelContextService: ref.watch(travelContextServiceProvider),
    sessionService: ref.watch(travelSessionServiceProvider),
    batteryOptimizationService: ref.watch(batteryOptimizationServiceProvider),
    offlineLocationService: ref.watch(offlineLocationServiceProvider),
    cache: ref.watch(gpsCacheServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
