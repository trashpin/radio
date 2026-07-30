import 'dart:async';

import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/services/location_provider.dart';

/// Subscribes to the active [LocationProvider] and forwards fixes, managing the
/// subscription lifecycle (start/pause/resume/stop).
///
/// WHY THIS EXISTS: it isolates stream/subscription plumbing from the engine's
/// decision logic. The GPSService just says "start, and call me on each fix";
/// this service handles provider start/stop and pause/resume. Swapping the
/// underlying provider (system/Google/Apple/offline/background) requires no
/// change here.
class LocationTrackingService {
  LocationTrackingService(this._provider);

  final LocationProvider _provider;
  StreamSubscription<GPSLocation>? _subscription;
  GPSLocation? _last;

  GPSLocation? get last => _last;
  bool get isTracking => _subscription != null && !_subscription!.isPaused;

  Future<void> start(void Function(GPSLocation fix) onFix) async {
    // Subscribe BEFORE start(): the provider emits the initial fix (last-known +
    // getCurrentPosition) during start(), and its stream is a broadcast stream
    // that drops events when there's no listener yet. Subscribing first means a
    // stationary user's very first fix is delivered (previously it was lost, so
    // the app sat on "finding your location" until the user moved ≥5 m).
    _subscription = _provider.stream.listen((fix) {
      _last = fix;
      onFix(fix);
    });
    await _provider.start();
  }

  void pause() => _subscription?.pause();
  void resume() => _subscription?.resume();

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _provider.stop();
  }
}
