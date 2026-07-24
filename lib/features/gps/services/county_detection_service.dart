import 'package:explorer_os_mobile/features/gps/models/county_boundary.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';

/// Determines which county a fix falls within.
///
/// WHY THIS EXISTS: "current county" is a TravelContext signal (and drives
/// Entered/ExitedCounty events). Mirrors [StateDetectionService]; extracting it
/// keeps the engine lean and lets county detection evolve (bbox → polygon)
/// independently.
class CountyDetectionService {
  final List<CountyBoundary> _counties = [];

  void setCounties(List<CountyBoundary> counties) {
    _counties
      ..clear()
      ..addAll(counties);
  }

  CountyBoundary? detect(GPSLocation loc) {
    for (final county in _counties) {
      if (county.contains(loc.latitude, loc.longitude)) return county;
    }
    return null;
  }
}
