import 'package:explorer_os_mobile/features/gps/models/geofence.dart';
import 'package:explorer_os_mobile/features/gps/services/geofence_selector.dart';

/// Lightweight geofence intelligence layer.
///
/// This class deliberately does NOT own GPS tracking and does NOT modify
/// GPSService or GeofenceService. It receives a GPS coordinate and a list of
/// database geofences and determines the best matching hierarchical fence.
class GeofenceIntelligenceService {
  GeofenceIntelligenceService({
    this._selector = const GeofenceSelector(),
  });

  final GeofenceSelector _selector;

  GeofenceMatch? _current;

  /// The geofence currently selected by the intelligence layer.
  GeofenceMatch? get current => _current;

  /// Evaluate a GPS coordinate against the supplied geofences.
  ///
  /// Returns the newly selected match, or null if no active geofence contains
  /// the coordinate.
  GeofenceMatch? evaluate({
    required List<Geofence> geofences,
    required double latitude,
    required double longitude,
  }) {
    final match = _selector.selectBest(
      geofences: geofences,
      latitude: latitude,
      longitude: longitude,
    );

    _current = match;
    return match;
  }

  /// Clears the currently selected geofence.
  void reset() {
    _current = null;
  }
}
