import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/services/destination_detector.dart';
import 'package:explorer_os_mobile/features/gps/services/geofence_engine.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_cache_service.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_service.dart';
import 'package:explorer_os_mobile/features/gps/services/heading_service.dart';
import 'package:explorer_os_mobile/features/gps/services/location_monitor.dart';
import 'package:explorer_os_mobile/features/gps/services/location_provider.dart';
import 'package:explorer_os_mobile/features/gps/services/park_detector.dart';
import 'package:explorer_os_mobile/features/gps/services/route_engine.dart';
import 'package:explorer_os_mobile/features/gps/services/speed_service.dart';
import 'package:explorer_os_mobile/features/gps/services/travel_context_service.dart';

/// Dependency-injection wiring for the GPS Intelligence Engine.
///
/// Every sub-service is a scope singleton so they share state across a fix
/// (route distance, park state, geofence membership). The default
/// [locationProviderProvider] is a [SimulatedLocationProvider] — override it in
/// `main`/tests with a real provider (system/Google/Apple/offline) to go live.

final locationProviderProvider = Provider<LocationProvider>((ref) {
  final provider = SimulatedLocationProvider();
  ref.onDispose(provider.dispose);
  return provider;
});

final speedServiceProvider = Provider<SpeedService>((ref) => const SpeedService());
final headingServiceProvider =
    Provider<HeadingService>((ref) => const HeadingService());
final routeEngineProvider = Provider<RouteEngine>((ref) => RouteEngine());
final geofenceEngineProvider = Provider<GeofenceEngine>((ref) => GeofenceEngine());
final parkDetectorProvider = Provider<ParkDetector>((ref) => ParkDetector());
final destinationDetectorProvider =
    Provider<DestinationDetector>((ref) => DestinationDetector());
final travelContextServiceProvider =
    Provider<TravelContextService>((ref) => const TravelContextService());
final gpsCacheServiceProvider =
    Provider<GPSCacheService>((ref) => GPSCacheService());

final locationMonitorProvider = Provider<LocationMonitor>((ref) {
  return LocationMonitor(ref.watch(locationProviderProvider));
});

/// The composed GPS Intelligence Engine.
final gpsServiceProvider = Provider<GPSService>((ref) {
  final service = GPSService(
    monitor: ref.watch(locationMonitorProvider),
    speedService: ref.watch(speedServiceProvider),
    headingService: ref.watch(headingServiceProvider),
    routeEngine: ref.watch(routeEngineProvider),
    geofenceEngine: ref.watch(geofenceEngineProvider),
    parkDetector: ref.watch(parkDetectorProvider),
    destinationDetector: ref.watch(destinationDetectorProvider),
    travelContextService: ref.watch(travelContextServiceProvider),
    cache: ref.watch(gpsCacheServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
