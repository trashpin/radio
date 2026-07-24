import 'package:explorer_os_mobile/core/data/model.dart';

/// The extent of a county, used to detect the current county.
///
/// Read-only backend content ([Model]). Bounding box for a fast membership test
/// (mirrors [StateBoundary]); a precise polygon can replace [contains] later.
class CountyBoundary implements Model {
  const CountyBoundary({
    required this.id,
    required this.name,
    required this.stateCode,
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  @override
  final String id;
  final String name;
  final String stateCode;
  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  bool contains(double lat, double lng) =>
      lat >= minLatitude &&
      lat <= maxLatitude &&
      lng >= minLongitude &&
      lng <= maxLongitude;

  factory CountyBoundary.fromJson(Json json) => CountyBoundary(
        id: json['id']?.toString() ?? '',
        name: (json['name'] ?? '') as String,
        stateCode: (json['state_code'] ?? '') as String,
        minLatitude: (json['min_latitude'] as num?)?.toDouble() ?? 0,
        maxLatitude: (json['max_latitude'] as num?)?.toDouble() ?? 0,
        minLongitude: (json['min_longitude'] as num?)?.toDouble() ?? 0,
        maxLongitude: (json['max_longitude'] as num?)?.toDouble() ?? 0,
      );
}
