import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/services/location_provider.dart';

/// Real device positioning via the `geolocator` package — the production
/// implementation of [LocationProvider].
///
/// WHY THIS EXISTS: it is the concrete adapter behind the engine's
/// provider-agnostic seam. The GPS engine depends only on [LocationProvider], so
/// this class (and its permission handling + `Position` → [GPSLocation] mapping)
/// is the ONLY place tied to `geolocator`. Swap it for Google/Apple/offline
/// providers by overriding `locationProviderProvider`.
///
/// Permission/service checks run lazily in [start]/[current] so merely
/// constructing the provider (e.g. on web or in tests) never prompts the user.
/// The pure [toGpsLocation] mapping is exposed for unit testing without a device.
class GeolocatorLocationProvider implements LocationProvider {
  GeolocatorLocationProvider({
    this.settings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  });

  /// Accuracy + distance filter applied to the position stream. A caller can
  /// tune this from `BatteryOptimizationService.recommend(...)`.
  final LocationSettings settings;

  StreamController<GPSLocation>? _controller;
  StreamSubscription<Position>? _subscription;

  @override
  GpsProviderType get type => GpsProviderType.system;

  @override
  Stream<GPSLocation> get stream {
    _controller ??= StreamController<GPSLocation>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<GPSLocation?> current() async {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return toGpsLocation(last);
    if (!await _ensurePermission()) return null;
    final position =
        await Geolocator.getCurrentPosition(locationSettings: settings);
    return toGpsLocation(position);
  }

  @override
  Future<void> start() async {
    if (!await _ensurePermission()) return;
    _controller ??= StreamController<GPSLocation>.broadcast();
    _subscription ??= Geolocator.getPositionStream(locationSettings: settings)
        .listen((position) => _controller?.add(toGpsLocation(position)),
            onError: (_) {});
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Ensures location services are on and permission is granted.
  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Pure mapping from a geolocator [Position] to the engine's [GPSLocation].
  static GPSLocation toGpsLocation(Position position) => GPSLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: position.timestamp,
        accuracyMeters: position.accuracy,
        headingDegrees: position.heading,
        speedMps: position.speed,
        elevationMeters: position.altitude,
      );

  void dispose() {
    _subscription?.cancel();
    _controller?.close();
  }
}
