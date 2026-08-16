import 'dart:async';

import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';

/// The abstraction that decouples the engine from any specific positioning
/// backend.
///
/// WHY THIS EXISTS: to prepare for multiple providers — system geolocation,
/// Google Maps, Apple Maps, or offline/downloaded-map positioning — without the
/// engine caring which is active. A real implementation (e.g. wrapping
/// `geolocator`) simply implements this interface and is swapped in via the
/// provider. The engine only ever depends on this contract.
abstract class LocationProvider {
  GpsProviderType get type;

  /// A stream of fixes while tracking is active.
  Stream<GPSLocation> get stream;

  /// The most recent fix, if any.
  Future<GPSLocation?> current();

  Future<void> start();
  Future<void> stop();
}

/// Default provider used until a real one is wired in.
///
/// Emits nothing on its own, but exposes [emit] so tests and demos can drive the
/// engine deterministically with scripted fixes. This mirrors the "no real I/O
/// yet" approach used elsewhere (the Radio Engine plays no audio).
class SimulatedLocationProvider implements LocationProvider {
  final StreamController<GPSLocation> _controller =
      StreamController<GPSLocation>.broadcast();
  GPSLocation? _last;

  @override
  GpsProviderType get type => GpsProviderType.simulated;

  @override
  Stream<GPSLocation> get stream => _controller.stream;

  @override
  Future<GPSLocation?> current() async => _last;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  /// Push a scripted fix through the stream (for tests/simulation).
  void emit(GPSLocation location) {
    _last = location;
    _controller.add(location);
  }

  void dispose() => _controller.close();
}
