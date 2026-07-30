import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_status.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_logger.dart';
import 'package:explorer_os_mobile/features/gps/services/location_provider.dart';

/// Real device positioning via the `geolocator` package — the production
/// implementation of [LocationProvider].
///
/// WHY THIS EXISTS: it is the concrete adapter behind the engine's
/// provider-agnostic seam. The GPS engine depends only on [LocationProvider], so
/// this class (permission handling + `Position` → [GPSLocation] mapping) is the
/// ONLY place tied to `geolocator`.
///
/// Repairs (GPS audit):
/// - [start] now fetches an IMMEDIATE fix via `getCurrentPosition` before
///   subscribing to the stream, so a stationary visitor gets a location right
///   away (the old code only subscribed with a distance filter, so no fix
///   arrived until the user moved ≥10 m).
/// - Permission/service state is resolved into a normalized
///   [LocationPermissionStatus] covering every case, and every step is logged.
/// - Stream errors are caught and surfaced as GPS lost/restored — never crash.
class GeolocatorLocationProvider implements LocationProvider {
  GeolocatorLocationProvider({
    this.settings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      // Small filter so we keep receiving fixes without excessive churn; the
      // immediate initial fix in [start] covers the stationary case.
      distanceFilter: 5,
    ),
    this.initialFixTimeout = const Duration(seconds: 30),
    this.logger,
  });

  /// Accuracy + distance filter applied to the position stream.
  final LocationSettings settings;

  /// How long to wait for the first fix before falling back to the stream.
  final Duration initialFixTimeout;

  final GpsLogger? logger;

  StreamController<GPSLocation>? _controller;
  StreamSubscription<Position>? _subscription;
  bool _streamHealthy = true;

  LocationPermissionStatus _lastPermission = LocationPermissionStatus.unknown;
  LocationPermissionStatus get lastPermission => _lastPermission;

  @override
  GpsProviderType get type => GpsProviderType.system;

  @override
  Stream<GPSLocation> get stream {
    _controller ??= StreamController<GPSLocation>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<GPSLocation?> current() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return toGpsLocation(last);
    } catch (_) {
      // getLastKnownPosition is unsupported on web — fall through.
    }
    final status = await resolvePermission();
    if (!status.isGranted) return null;
    try {
      final position =
          await Geolocator.getCurrentPosition(locationSettings: settings);
      return toGpsLocation(position);
    } catch (e) {
      logger?.error('current() failed: $e');
      return null;
    }
  }

  @override
  Future<void> start() async {
    final status = await resolvePermission();
    _lastPermission = status;
    if (!status.isGranted) {
      logger?.permissionDenied(status.name);
      return; // The caller reads [lastPermission] / GpsStatus for messaging.
    }
    _controller ??= StreamController<GPSLocation>.broadcast();

    // 1a) Seed from the device's last-known location INSTANTLY so the user is
    // placed on the map right away while a fresh fix is acquired (cold GPS
    // starts can take 15-30s outdoors — the user should never sit on a blank
    // "searching" screen when a cached location exists).
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) _emit(toGpsLocation(last));
    } catch (_) {
      // Unsupported on web / no cached fix — fall through.
    }

    // 1b) A fresh precise fix (longer timeout for a cold start).
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      ).timeout(initialFixTimeout);
      _emit(toGpsLocation(position));
    } catch (e) {
      logger?.error('initial fix unavailable: $e');
    }

    logger?.initialized();

    // 2) Continuous updates.
    _subscription ??= Geolocator.getPositionStream(locationSettings: settings)
        .listen(
      (position) {
        if (!_streamHealthy) {
          _streamHealthy = true;
          logger?.gpsRestored();
        }
        _emit(toGpsLocation(position));
      },
      onError: (Object e) {
        if (_streamHealthy) {
          _streamHealthy = false;
          logger?.gpsLost('$e');
        }
      },
    );
    logger?.subscriptionStarted();
  }

  void _emit(GPSLocation fix) {
    _controller?.add(fix);
    logger?.locationUpdated(fix);
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    logger?.subscriptionStopped();
  }

  /// Resolves (and optionally requests) permission into a normalized status,
  /// covering: services disabled, denied, permanently denied, and granted.
  Future<LocationPermissionStatus> resolvePermission({bool request = true}) async {
    logger?.permissionRequested();
    bool serviceEnabled;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      logger?.error('service check failed: $e');
      serviceEnabled = false;
    }
    if (!serviceEnabled) {
      _lastPermission = LocationPermissionStatus.serviceDisabled;
      logger?.permissionDenied('service disabled');
      return _lastPermission;
    }

    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && request) {
        permission = await Geolocator.requestPermission();
      }
    } catch (e) {
      logger?.error('permission check failed: $e');
      _lastPermission = LocationPermissionStatus.denied;
      return _lastPermission;
    }

    _lastPermission = _mapPermission(permission);
    if (_lastPermission.isGranted) {
      logger?.permissionGranted(_lastPermission.name);
    } else {
      logger?.permissionDenied(_lastPermission.name);
    }
    return _lastPermission;
  }

  /// Current permission WITHOUT prompting (for UI status).
  Future<LocationPermissionStatus> checkPermission() =>
      resolvePermission(request: false);

  /// Opens the OS app-settings page (for a permanently-denied recovery flow).
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Opens the OS location-services settings page.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  static LocationPermissionStatus _mapPermission(LocationPermission p) =>
      switch (p) {
        LocationPermission.always => LocationPermissionStatus.grantedAlways,
        LocationPermission.whileInUse =>
          LocationPermissionStatus.grantedWhenInUse,
        LocationPermission.deniedForever =>
          LocationPermissionStatus.deniedForever,
        LocationPermission.denied => LocationPermissionStatus.denied,
        LocationPermission.unableToDetermine =>
          LocationPermissionStatus.unknown,
      };

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
