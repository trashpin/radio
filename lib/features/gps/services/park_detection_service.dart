import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/park_boundary.dart';

/// The park (if any) the user is in/near, plus their arrival status.
class ParkDetectionResult {
  const ParkDetectionResult({this.parkId, required this.arrivalStatus});
  final String? parkId;
  final ArrivalStatus arrivalStatus;
}

/// Determines the current park and drives the arrival state machine
/// (approaching → arrived → visiting → departing → left).
///
/// WHY THIS EXISTS: "which park am I in, and am I just arriving or leaving?" is a
/// core signal for audio (welcome messages on arrival, wrap-ups on departure).
/// This service owns that stateful interpretation so the rest of the engine
/// stays stateless about parks. Its transitions become Entered/ExitedPark and
/// arrival events.
class ParkDetectionService {
  final List<ParkBoundary> _parks = [];
  String? _currentParkId;

  void setParks(List<ParkBoundary> parks) {
    _parks
      ..clear()
      ..addAll(parks);
    _currentParkId = null;
  }

  ParkDetectionResult update(GPSLocation loc) {
    final inside = _firstWhereOrNull(
      _parks,
      (p) => p.contains(loc.latitude, loc.longitude),
    );

    if (inside != null) {
      final isNewArrival = _currentParkId != inside.parkId;
      _currentParkId = inside.parkId;
      return ParkDetectionResult(
        parkId: inside.parkId,
        arrivalStatus:
            isNewArrival ? ArrivalStatus.arrived : ArrivalStatus.visiting,
      );
    }

    // Not inside any park. If we just left one, report departing once.
    if (_currentParkId != null) {
      final departedPark = _currentParkId;
      _currentParkId = null;
      return ParkDetectionResult(
        parkId: departedPark,
        arrivalStatus: ArrivalStatus.departing,
      );
    }

    // Approaching a park's outer zone?
    final approaching = _firstWhereOrNull(
      _parks,
      (p) => p.isApproaching(loc.latitude, loc.longitude),
    );
    if (approaching != null) {
      return ParkDetectionResult(
        parkId: approaching.parkId,
        arrivalStatus: ArrivalStatus.approaching,
      );
    }

    return const ParkDetectionResult(arrivalStatus: ArrivalStatus.left);
  }

  T? _firstWhereOrNull<T>(List<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }
}
