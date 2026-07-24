import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';

/// A geofenced audio trigger: "when the listener enters this area, play this."
///
/// Read-only backend content that PREPARES the engine for GPS without
/// implementing location yet. The [GPSAudioScheduler] loads these but does not
/// evaluate them until real positioning is wired in. Modeling them now means
/// the schema, repository, and engine seam are all in place for a drop-in GPS
/// feature later.
class GPSAudioTrigger implements Model {
  const GPSAudioTrigger({
    required this.id,
    required this.title,
    required this.location,
    this.radiusMeters = 150,
    this.narrationId,
    this.audioUrl,
    this.durationSeconds,
    this.parkId,
    this.state,
    this.oneShot = true,
    this.tags = const [],
  });

  @override
  final String id;
  final String title;

  /// Center of the geofence that arms this trigger.
  final GeoPoint location;

  /// Radius (meters) within which the trigger fires.
  final double radiusMeters;

  final String? narrationId;
  final String? audioUrl;
  final int? durationSeconds;
  final String? parkId;
  final String? state;

  /// If true, the trigger fires only once per session.
  final bool oneShot;
  final List<String> tags;

  factory GPSAudioTrigger.fromJson(Json json) => GPSAudioTrigger(
        id: json['id']?.toString() ?? '',
        title: (json['title'] ?? '') as String,
        location: GeoPoint.fromJson(json),
        radiusMeters: (json['radius_meters'] as num?)?.toDouble() ?? 150,
        narrationId: json['narration_id']?.toString(),
        audioUrl: json['audio_url'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        parkId: json['park_id']?.toString(),
        state: json['state'] as String?,
        oneShot: (json['one_shot'] ?? true) as bool,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      );
}
