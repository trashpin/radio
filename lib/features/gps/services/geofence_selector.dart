import 'package:explorer_os_mobile/features/gps/models/geofence.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';

/// Selects the most specific active geofence containing a GPS position.
///
/// This class is intentionally independent of GPS, Supabase, Riverpod,
/// audio, and UI. It only evaluates geofence data that is supplied to it.
class GeofenceSelector {
  const GeofenceSelector();

  GeofenceMatch? selectBest({
    required List<Geofence> geofences,
    required double latitude,
    required double longitude,
  }) {
    final matches = <GeofenceMatch>[];

    for (final geofence in geofences) {
      if (!geofence.active) {
        continue;
      }

      final distanceMeters = GeoMath.distanceMeters(
        geofence.centerLat,
        geofence.centerLng,
        latitude,
        longitude,
      );

      if (distanceMeters <= geofence.radiusMeters) {
        matches.add(
          GeofenceMatch(
            geofence: geofence,
            distanceMeters: distanceMeters,
          ),
        );
      }
    }

    if (matches.isEmpty) {
      return null;
    }

    matches.sort((a, b) {
      // Most specific hierarchy level wins.
      final depthCompare =
          b.geofence.level.depth.compareTo(a.geofence.level.depth);

      if (depthCompare != 0) {
        return depthCompare;
      }

      // Priority only breaks ties at the same hierarchy depth.
      final priorityCompare = b.geofence.effectivePriority
          .compareTo(a.geofence.effectivePriority);

      if (priorityCompare != 0) {
        return priorityCompare;
      }

      // Final deterministic tie-breaker: closest center.
      return a.distanceMeters.compareTo(b.distanceMeters);
    });

    return matches.first;
  }
}
