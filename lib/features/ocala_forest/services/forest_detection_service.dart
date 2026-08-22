import 'package:explorer_os_mobile/features/ocala_forest/models/forest_boundary.dart';

/// Determines whether a GPS fix is inside a [ForestBoundary]. Deliberately
/// simpler than `ParkDetectionService` (no approach/arrival state machine) —
/// v1 success criterion is just "know whether the user is inside or outside
/// the forest," per the spec's section 7.
class ForestDetectionService {
  const ForestDetectionService();

  bool isInside(ForestBoundary boundary, double lat, double lng) =>
      boundary.contains(lat, lng);
}
