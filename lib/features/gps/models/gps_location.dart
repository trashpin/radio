import 'package:explorer_os_mobile/core/data/model.dart';

/// A single positioning fix from whichever [LocationProvider] is active.
///
/// The atomic input to the whole engine. Everything else (speed, heading,
/// geofencing, detection) is derived from a stream of these. Serializable so
/// fixes can be cached for offline continuity.
class GPSLocation {
  const GPSLocation({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracyMeters,
    this.headingDegrees,
    this.speedMps,
    this.elevationMeters,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;

  /// Horizontal accuracy in meters (smaller is better), when reported.
  final double? accuracyMeters;

  /// Device-reported heading in degrees (0–360), when available.
  final double? headingDegrees;

  /// Device-reported ground speed in meters/second, when available.
  final double? speedMps;

  final double? elevationMeters;

  factory GPSLocation.fromJson(Json json) => GPSLocation(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
            DateTime.now(),
        accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
        headingDegrees: (json['heading_degrees'] as num?)?.toDouble(),
        speedMps: (json['speed_mps'] as num?)?.toDouble(),
        elevationMeters: (json['elevation_meters'] as num?)?.toDouble(),
      );

  Json toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
        if (headingDegrees != null) 'heading_degrees': headingDegrees,
        if (speedMps != null) 'speed_mps': speedMps,
        if (elevationMeters != null) 'elevation_meters': elevationMeters,
      };
}
