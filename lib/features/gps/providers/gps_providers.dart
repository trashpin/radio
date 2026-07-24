import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/services/destination_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/distance_service.dart';
import 'package:explorer_os_mobile/features/gps/services/geofence_service.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_cache_service.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_service.dart';
import 'package:explorer_os_mobile/features/gps/services/heading_service.dart';
import 'package:explorer_os_mobile/features/gps/services/location_provider.dart';
import 'package:explorer_os_mobile/features/gps/services/location_tracking_service.dart';
import 'package:explorer_os_mobile/features/gps/services/park_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/route_engine.dart';
import 'package:explorer_os_mobile/features/gps/services/speed_service.dart';
import 'package:explorer_os_mobile/features/gps/services/state_detection_service.dart';
import 'package:explorer_os_mobile/features/gps/services/travel_context_service.dart';

/// Dependency-injection wiring for the GPS Intelligence Engine.
///
/// Every sub-service is a scope singleton so they share state across a fix
/// (route distance, park state, geofence membership). The default
/// [locationProviderProvider] is a [SimulatedLocationProvider] — override it in
/// `main`/tests with a real provider (system/Google/Apple/offline/background) to
/// go live.

final locationProviderProvider = Provider<LocationProvider>((ref) {
  final provider = SimulatedLocationProvider();
  ref.onDispose(provider.dispose);
  return provider;
});

final speedServiceProvider =
    Provider<SpeedService>((ref) => const SpeedService());
final headingServiceProvider =
    Provider<HeadingService>((ref) => const HeadingService());
final distanceServiceProvider =
    Provider<DistanceService>((ref) => const DistanceService());
final routeEngineProvider = Provider<RouteEngine>((ref) => RouteEngine());
final geofenceServiceProvider =
    Provider<GeofenceService>((ref) => GeofenceService());
final parkDetectionServiceProvider =
    Provider<ParkDetectionService>((ref) => ParkDetectionService());
final destinationDetectionServiceProvider =
    Provider<DestinationDetectionService>(
        (ref) => DestinationDetectionService());
final stateDetectionServiceProvider =
    Provider<StateDetectionService>((ref) => StateDetectionService());
final travelContextServiceProvider =
    Provider<TravelContextService>((ref) => const TravelContextService());
final gpsCacheServiceProvider =
    Provider<GPSCacheService>((ref) => GPSCacheService());

final locationTrackingServiceProvider = Provider<LocationTrackingService>(
  (ref) => LocationTrackingService(ref.watch(locationProviderProvider)),
);

/// The composed GPS Intelligence Engine.
final gpsServiceProvider = Provider<GPSService>((ref) {
  final service = GPSService(
    tracking: ref.watch(locationTrackingServiceProvider),
    speedService: ref.watch(speedServiceProvider),
    headingService: ref.watch(headingServiceProvider),
    distanceService: ref.watch(distanceServiceProvider),
    routeEngine: ref.watch(routeEngineProvider),
    geofenceService: ref.watch(geofenceServiceProvider),
    parkDetectionService: ref.watch(parkDetectionServiceProvider),
    destinationDetectionService:
        ref.watch(destinationDetectionServiceProvider),
    stateDetectionService: ref.watch(stateDetectionServiceProvider),
    travelContextService: ref.watch(travelContextServiceProvider),
    cache: ref.watch(gpsCacheServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
