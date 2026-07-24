import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/state_boundary.dart';

/// Determines which US state (or region) a fix falls within.
///
/// WHY THIS EXISTS: "current state" is a first-class TravelContext signal (and
/// drives Entered/ExitedState events). Extracting it into its own service keeps
/// the GPSService lean and lets state detection evolve (bounding box today,
/// precise polygons later) without touching the engine.
class StateDetectionService {
  final List<StateBoundary> _states = [];

  void setStates(List<StateBoundary> states) {
    _states
      ..clear()
      ..addAll(states);
  }

  /// The first boundary that contains the fix, or null if none/outside data.
  StateBoundary? detect(GPSLocation loc) {
    for (final state in _states) {
      if (state.contains(loc.latitude, loc.longitude)) return state;
    }
    return null;
  }
}
