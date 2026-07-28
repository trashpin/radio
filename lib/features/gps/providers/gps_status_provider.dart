import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_status.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_providers.dart';
import 'package:explorer_os_mobile/features/gps/services/geolocator_location_provider.dart';

/// The app-wide live GPS status — the single surface every system (Around Me,
/// Playback Manager, Experience Intelligence, Explorer Radio) reads to know the
/// visitor's current position, accuracy, movement, permission, and health.
///
/// It updates from every fix the GPS engine emits (real device OR the
/// simulator, since both flow through [gpsControllerProvider]).
final gpsStatusProvider =
    NotifierProvider<GpsStatusController, GpsStatus>(GpsStatusController.new);

class GpsStatusController extends Notifier<GpsStatus> {
  @override
  GpsStatus build() {
    ref.listen<TravelContext>(gpsControllerProvider, (_, ctx) => _onFix(ctx));
    return GpsStatus.initial();
  }

  void _onFix(TravelContext ctx) {
    final loc = ctx.location;
    if (loc == null) return;
    state = state.copyWith(
      latitude: loc.latitude,
      longitude: loc.longitude,
      accuracyMeters: loc.accuracyMeters,
      headingDegrees: ctx.bearingDegrees ?? loc.headingDegrees,
      speedMps: ctx.speed?.metersPerSecond ?? loc.speedMps,
      altitudeMeters: loc.elevationMeters,
      lastUpdate: loc.timestamp,
      updateCount: state.updateCount + 1,
      tracking: true,
      serviceEnabled: true,
      // Once fixes flow we treat permission as granted (covers the simulator,
      // which bypasses the OS permission layer).
      permission: state.permission.isGranted
          ? state.permission
          : LocationPermissionStatus.grantedWhenInUse,
    );
  }

  /// Requests permission (if needed) and begins live tracking. Safe to call
  /// repeatedly; on denial it leaves tracking off so a later retry can prompt
  /// again. Never throws.
  Future<GpsStatus> requestAndStart() async {
    final provider = ref.read(locationProviderProvider);
    var granted = true;
    if (provider is GeolocatorLocationProvider) {
      final permission = await provider.resolvePermission();
      granted = permission.isGranted;
      state = state.copyWith(
        permission: permission,
        serviceEnabled:
            permission != LocationPermissionStatus.serviceDisabled,
      );
    }
    if (granted) {
      try {
        await ref.read(gpsControllerProvider.notifier).startTracking();
        state = state.copyWith(tracking: true);
      } catch (_) {
        // Never crash on start failures; status already reflects reality.
      }
    }
    return state;
  }

  /// Re-checks permission WITHOUT prompting (e.g. after returning from system
  /// settings).
  Future<void> refreshPermission() async {
    final provider = ref.read(locationProviderProvider);
    if (provider is GeolocatorLocationProvider) {
      final permission = await provider.checkPermission();
      state = state.copyWith(
        permission: permission,
        serviceEnabled:
            permission != LocationPermissionStatus.serviceDisabled,
      );
    }
  }

  /// Opens the appropriate OS settings page to recover from a denied state.
  Future<void> openSettings() async {
    final provider = ref.read(locationProviderProvider);
    if (provider is! GeolocatorLocationProvider) return;
    if (state.permission == LocationPermissionStatus.serviceDisabled) {
      await provider.openLocationSettings();
    } else {
      await provider.openAppSettings();
    }
  }
}
