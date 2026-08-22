import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/navigation/models/trip_progress.dart';
import 'package:explorer_os_mobile/features/navigation/services/trip_tracker.dart';

/// Riverpod glue for [TripTracker] — the "Start Trip" action's home. Feeds
/// every GPS fix from the existing [gpsControllerProvider] into the tracker
/// (no second location stream) and republishes its [TripProgress] as state.
///
/// Event consumers (the Copilot Brain) subscribe directly to
/// `ref.read(tripControllerProvider.notifier).events` rather than through a
/// second provider layer — a plain broadcast stream is all that's needed.
class TripController extends Notifier<TripProgress> {
  late final TripTracker _tracker;

  @override
  TripProgress build() {
    _tracker = TripTracker();
    ref.listen<TravelContext>(gpsControllerProvider, (prev, next) {
      final loc = next.location;
      if (loc == null) return;
      _tracker.onLocation(loc).then((_) {
        state = _tracker.progress;
      });
    });
    ref.onDispose(_tracker.dispose);
    return TripProgress.idleState;
  }

  Stream<TripEvent> get events => _tracker.events;

  /// Starts a new tracked trip from the traveler's current GPS fix to
  /// (lat,lng). No-ops (and leaves state unchanged) without a current fix.
  Future<void> startTrip({
    required double lat,
    required double lng,
    String? name,
  }) async {
    final origin = ref.read(gpsControllerProvider).location;
    if (origin == null) return;
    await _tracker.start(
      originLat: origin.latitude,
      originLng: origin.longitude,
      destinationLat: lat,
      destinationLng: lng,
      destinationName: name,
    );
    state = _tracker.progress;
  }

  void cancelTrip() {
    _tracker.cancel();
    state = _tracker.progress;
  }
}

final tripControllerProvider =
    NotifierProvider<TripController, TripProgress>(TripController.new);
