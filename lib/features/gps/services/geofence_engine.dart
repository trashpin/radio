import 'package:explorer_os_mobile/features/gps/models/geofence_region.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';

/// A detected geofence transition.
enum GeofenceTransition { enter, exit }

class GeofenceEvent {
  const GeofenceEvent(this.region, this.transition);
  final GeofenceRegion region;
  final GeofenceTransition transition;
}

/// Watches a set of [GeofenceRegion]s and reports enter/exit transitions as the
/// user moves.
///
/// WHY THIS EXISTS: enter/exit detection is the primitive that powers park
/// arrival, attraction proximity, and (later) GPS-triggered audio. Centralizing
/// the "was inside / now inside" bookkeeping here keeps detectors simple and
/// avoids duplicating membership tracking.
class GeofenceEngine {
  final List<GeofenceRegion> _regions = [];
  final Set<String> _inside = {};

  List<GeofenceRegion> get regions => List.unmodifiable(_regions);

  void setRegions(List<GeofenceRegion> regions) {
    _regions
      ..clear()
      ..addAll(regions);
    _inside.clear();
  }

  /// Evaluates a new position and returns any enter/exit transitions since the
  /// previous evaluation.
  List<GeofenceEvent> evaluate(GPSLocation location) {
    final events = <GeofenceEvent>[];
    for (final region in _regions) {
      final isInsideNow = region.contains(location.latitude, location.longitude);
      final wasInside = _inside.contains(region.id);
      if (isInsideNow && !wasInside) {
        _inside.add(region.id);
        events.add(GeofenceEvent(region, GeofenceTransition.enter));
      } else if (!isInsideNow && wasInside) {
        _inside.remove(region.id);
        events.add(GeofenceEvent(region, GeofenceTransition.exit));
      }
    }
    return events;
  }

  bool isInside(String regionId) => _inside.contains(regionId);
}
