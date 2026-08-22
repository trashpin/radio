/// The kind of maneuver a [RouteStep] asks the driver to make. Parsed loosely
/// from Google Directions' own `maneuver` string (e.g. `"turn-left"`,
/// `"roundabout-right"`) — unrecognized/absent values fall back to [straight],
/// which is also what a plain "continue on X" step reports.
enum ManeuverKind {
  depart,
  straight,
  slightLeft,
  slightRight,
  turnLeft,
  turnRight,
  sharpLeft,
  sharpRight,
  uturn,
  merge,
  roundabout,
  arrive;

  static ManeuverKind fromGoogle(String? maneuver) {
    final m = (maneuver ?? '').toLowerCase();
    if (m.contains('depart')) return ManeuverKind.depart;
    if (m.contains('arrive') || m.contains('destination')) {
      return ManeuverKind.arrive;
    }
    if (m.contains('uturn')) return ManeuverKind.uturn;
    if (m.contains('roundabout')) return ManeuverKind.roundabout;
    if (m.contains('merge') || m.contains('fork') || m.contains('ramp')) {
      return ManeuverKind.merge;
    }
    if (m.contains('sharp-left')) return ManeuverKind.sharpLeft;
    if (m.contains('sharp-right')) return ManeuverKind.sharpRight;
    if (m.contains('slight-left')) return ManeuverKind.slightLeft;
    if (m.contains('slight-right')) return ManeuverKind.slightRight;
    if (m.contains('turn-left')) return ManeuverKind.turnLeft;
    if (m.contains('turn-right')) return ManeuverKind.turnRight;
    return ManeuverKind.straight;
  }
}

/// One instruction along a route — Google Directions' own wording (already
/// clear and correct), never rewritten or paraphrased by the copilot.
class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.maneuver,
    required this.distanceMeters,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
  });

  /// Google's own plain-text instruction (HTML tags already stripped),
  /// e.g. "Turn right onto Baseline Rd".
  final String instruction;
  final ManeuverKind maneuver;

  /// Length of this step, in meters.
  final double distanceMeters;

  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
}

/// A driving route from an origin to a destination — the parsed shape of a
/// single Google Directions API response. [polyline] is every step's start
/// point followed by the final step's end point, in order; used only for
/// off-route distance checks, never rendered (this feature ships no map UI).
class RoutePlan {
  const RoutePlan({
    required this.steps,
    required this.polyline,
    required this.totalDistanceMeters,
    this.destinationName,
  });

  final List<RouteStep> steps;
  final List<({double lat, double lng})> polyline;
  final double totalDistanceMeters;
  final String? destinationName;

  bool get isEmpty => steps.isEmpty;
}
