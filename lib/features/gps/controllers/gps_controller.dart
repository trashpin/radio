import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_providers.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_service.dart';

/// The UI/consumer-facing facade for the GPS engine.
///
/// WHY THIS EXISTS: downstream code (the future Map UI, and the coordinator that
/// feeds the AI Producer) should watch ONE reactive surface rather than the many
/// services. This [Notifier] subscribes to the engine's [TravelContext] stream
/// and re-publishes each update as its state, and forwards tracking commands to
/// the [GPSService].
class GpsController extends Notifier<TravelContext> {
  GPSService get _service => ref.read(gpsServiceProvider);
  StreamSubscription<TravelContext>? _subscription;

  @override
  TravelContext build() {
    _subscription = _service.travelContextStream.listen((context) {
      state = context;
    });
    ref.onDispose(() => _subscription?.cancel());
    return _service.getTravelContext();
  }

  Future<void> startTracking() => _service.startTracking();
  Future<void> stopTracking() => _service.stopTracking();
  void pauseTracking() => _service.pauseTracking();
  void resumeTracking() => _service.resumeTracking();
}

/// The single provider widgets/coordinators watch to observe travel context.
final gpsControllerProvider =
    NotifierProvider<GpsController, TravelContext>(GpsController.new);
