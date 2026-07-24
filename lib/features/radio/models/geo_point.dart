import 'package:explorer_os_mobile/core/data/model.dart';

/// A simple latitude/longitude coordinate.
///
/// Used by audio segments and [GPSAudioTrigger]s to describe where an audio
/// item is relevant. Kept as a small, reusable value type so the future GPS
/// feature (and the Map feature) can share it without redefining coordinates.
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  factory GeoPoint.fromJson(Json json) => GeoPoint(
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      );

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';
}
