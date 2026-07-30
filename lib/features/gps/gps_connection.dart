import 'package:explorer_os_mobile/features/gps/models/gps_status.dart';

/// Overall GPS quality, from the fix accuracy.
enum GpsHealth {
  none('No signal'),
  poor('Poor'),
  fair('Fair'),
  good('Good'),
  excellent('Excellent');

  const GpsHealth(this.label);
  final String label;

  bool get usable => this == fair || this == good || this == excellent;
}

/// The connection phase the user is in — drives the status message + gating.
enum GpsPhase {
  checkingPermission,
  permissionDenied,
  permissionBlocked,
  gpsDisabled,
  searching,
  resolvingCounty,
  ready,
}

/// A single progress step shown in the status card.
class GpsStep {
  const GpsStep(this.label, this.state);
  final String label;
  final GpsStepState state;
}

enum GpsStepState { done, active, pending }

double metersToFeet(double m) => m * 3.28084;

String accuracyLabel(double? meters) {
  if (meters == null) return '—';
  final ft = metersToFeet(meters).round();
  return '$ft feet';
}

/// Accuracy → health. Tuned for a phone GPS (meters).
GpsHealth healthForAccuracy(double? meters) {
  if (meters == null) return GpsHealth.none;
  if (meters <= 8) return GpsHealth.excellent; // ~26 ft
  if (meters <= 18) return GpsHealth.good; // ~59 ft
  if (meters <= 45) return GpsHealth.fair; // ~148 ft
  return GpsHealth.poor;
}

/// The derived, user-facing GPS connection state.
class GpsConnectionState {
  const GpsConnectionState({
    required this.phase,
    required this.health,
    required this.message,
    required this.reliable,
    required this.steps,
    this.timedOut = false,
  });

  final GpsPhase phase;
  final GpsHealth health;
  final String message;

  /// True once we have a fix good enough to zoom the map / start Explorer Mode.
  final bool reliable;
  final List<GpsStep> steps;
  final bool timedOut;

  bool get needsAction =>
      phase == GpsPhase.permissionDenied ||
      phase == GpsPhase.permissionBlocked ||
      phase == GpsPhase.gpsDisabled;
}

/// Seconds of searching after which we show the "still searching" tips.
const kGpsSearchTimeoutSeconds = 20;

/// Derives the connection state from the live [status], the resolved [county]
/// (null until reverse-geocoded), and how long we've been [searchingSeconds].
GpsConnectionState deriveGpsConnection(
  GpsStatus status, {
  String? county,
  int searchingSeconds = 0,
}) {
  final perm = status.permission;
  final hasFix = status.hasFix;
  final health = healthForAccuracy(status.accuracyMeters);
  // A fix with unknown accuracy (e.g. simulator) still counts as reliable.
  final reliable = hasFix && (status.accuracyMeters == null || health.usable);

  GpsStep done(String l) => GpsStep(l, GpsStepState.done);
  GpsStep active(String l) => GpsStep(l, GpsStepState.active);
  GpsStep pending(String l) => GpsStep(l, GpsStepState.pending);

  if (perm == LocationPermissionStatus.serviceDisabled) {
    return GpsConnectionState(
      phase: GpsPhase.gpsDisabled,
      health: GpsHealth.none,
      message: 'GPS is currently turned off. ExplorerOS works best with GPS '
          'enabled.',
      reliable: false,
      steps: [pending('Enable GPS')],
    );
  }
  if (perm == LocationPermissionStatus.deniedForever) {
    return GpsConnectionState(
      phase: GpsPhase.permissionBlocked,
      health: GpsHealth.none,
      message: 'Location permission is blocked. Open Settings to let '
          'ExplorerOS find what\'s around you.',
      reliable: false,
      steps: [pending('Grant permission')],
    );
  }
  if (perm == LocationPermissionStatus.denied) {
    return GpsConnectionState(
      phase: GpsPhase.permissionDenied,
      health: GpsHealth.none,
      message: 'ExplorerOS uses your location for GPS-triggered stories, '
          'music, and nearby discoveries. Tap to allow access.',
      reliable: false,
      steps: [pending('Grant permission')],
    );
  }
  if (perm == LocationPermissionStatus.unknown && !hasFix) {
    return GpsConnectionState(
      phase: GpsPhase.checkingPermission,
      health: GpsHealth.none,
      message: 'Connecting to GPS…',
      reliable: false,
      steps: [active('Checking permission')],
    );
  }

  // Permission granted (or a fix exists). Searching → locating → county → ready.
  final baseSteps = [done('Permission granted'), done('GPS enabled')];

  if (!hasFix) {
    final timedOut = searchingSeconds >= kGpsSearchTimeoutSeconds;
    return GpsConnectionState(
      phase: GpsPhase.searching,
      health: GpsHealth.none,
      message: timedOut
          ? 'Still searching… this can happen indoors. For faster results, '
              'go outside, enable High Accuracy, and turn on Wi-Fi.'
          : 'Searching for satellites… finding your location.',
      reliable: false,
      timedOut: timedOut,
      steps: [...baseSteps, active('Locating you')],
    );
  }

  if ((county ?? '').trim().isEmpty) {
    return GpsConnectionState(
      phase: GpsPhase.resolvingCounty,
      health: health,
      message: 'Got your location — determining your county…',
      reliable: reliable,
      steps: [
        ...baseSteps,
        done('Located you'),
        active('Determining county'),
      ],
    );
  }

  return GpsConnectionState(
    phase: GpsPhase.ready,
    health: health,
    message: 'GPS connected — Explorer Mode ready.',
    reliable: reliable,
    steps: [
      ...baseSteps,
      done('Located you'),
      done('County: $county'),
      done('Explorer Mode ready'),
    ],
  );
}
