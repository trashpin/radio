import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';

/// A persisted, serializable snapshot of the user's travel at a moment.
///
/// Distinct from `LocationSnapshot` (an in-memory cache entry): this is the
/// record shape written to Supabase by the LocationRepository for trip history
/// and cross-device continuity. Implements [Model] + [toJson] for the generic
/// sync repository.
class TravelSnapshot implements Model {
  const TravelSnapshot({
    required this.id,
    required this.location,
    required this.movementState,
    required this.travelMode,
    this.stateCode,
    this.parkId,
    this.destinationId,
    this.distanceTravelledMeters = 0,
  });

  @override
  final String id;
  final GPSLocation location;
  final MovementState movementState;
  final TravelMode travelMode;
  final String? stateCode;
  final String? parkId;
  final String? destinationId;
  final double distanceTravelledMeters;

  DateTime get timestamp => location.timestamp;

  factory TravelSnapshot.fromJson(Json json) => TravelSnapshot(
        id: json['id']?.toString() ?? '',
        location: GPSLocation.fromJson(json),
        movementState: MovementState.values.firstWhere(
          (m) => m.name == json['movement_state'],
          orElse: () => MovementState.idle,
        ),
        travelMode: TravelMode.values.firstWhere(
          (m) => m.name == json['travel_mode'],
          orElse: () => TravelMode.stationary,
        ),
        stateCode: json['state_code'] as String?,
        parkId: json['park_id']?.toString(),
        destinationId: json['destination_id']?.toString(),
        distanceTravelledMeters:
            (json['distance_travelled_meters'] as num?)?.toDouble() ?? 0,
      );

  Json toJson() => {
        'id': id,
        ...location.toJson(),
        'movement_state': movementState.name,
        'travel_mode': travelMode.name,
        if (stateCode != null) 'state_code': stateCode,
        if (parkId != null) 'park_id': parkId,
        if (destinationId != null) 'destination_id': destinationId,
        'distance_travelled_meters': distanceTravelledMeters,
      };
}
