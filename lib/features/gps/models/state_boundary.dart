import 'package:explorer_os_mobile/core/data/model.dart';

/// The extent of a US state (or region), used to detect the current state.
///
/// Read-only backend content ([Model]). Uses a simple bounding box for a fast
/// membership test; a precise polygon can replace [contains] later. Sufficient
/// for the engine's "current state" signal.
class StateBoundary implements Model {
  const StateBoundary({
    required this.id,
    required this.code,
    required this.name,
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  @override
  final String id;
  final String code;
  final String name;
  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  bool contains(double lat, double lng) =>
      lat >= minLatitude &&
      lat <= maxLatitude &&
      lng >= minLongitude &&
      lng <= maxLongitude;

  factory StateBoundary.fromJson(Json json) => StateBoundary(
        id: json['id']?.toString() ?? '',
        code: (json['code'] ?? '') as String,
        name: (json['name'] ?? '') as String,
        minLatitude: (json['min_latitude'] as num?)?.toDouble() ?? 0,
        maxLatitude: (json['max_latitude'] as num?)?.toDouble() ?? 0,
        minLongitude: (json['min_longitude'] as num?)?.toDouble() ?? 0,
        maxLongitude: (json['max_longitude'] as num?)?.toDouble() ?? 0,
      );
}
