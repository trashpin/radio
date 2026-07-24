import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';

/// A point-in-time record of the user's location plus the context resolved at
/// that moment.
///
/// The GPSCacheService stores a rolling buffer of these to (a) support offline
/// continuity — the last known position/context survives signal loss — and
/// (b) power distance-travelled and "recently visited" logic without recomputing
/// from scratch.
class LocationSnapshot {
  const LocationSnapshot({
    required this.location,
    required this.movementState,
    this.stateCode,
    this.parkId,
    this.destinationId,
  });

  final GPSLocation location;
  final MovementState movementState;
  final String? stateCode;
  final String? parkId;
  final String? destinationId;

  DateTime get timestamp => location.timestamp;
}
