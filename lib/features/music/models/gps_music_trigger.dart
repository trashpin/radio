import 'package:explorer_os_mobile/core/data/model.dart';

/// Plays a specific song when the listener enters a geofence.
///
/// The music-library counterpart to the radio `GPSAudioTrigger` (which triggers
/// narration). Consumed by the GPS/AI-Producer path to surface a location song.
class GPSMusicTrigger implements Model {
  const GPSMusicTrigger({
    required this.id,
    required this.songId,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 300,
    this.parkId,
    this.state,
    this.oneShot = true,
  });

  @override
  final String id;
  final String songId;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String? parkId;
  final String? state;
  final bool oneShot;

  factory GPSMusicTrigger.fromJson(Json json) => GPSMusicTrigger(
        id: json['id']?.toString() ?? '',
        songId: json['song_id']?.toString() ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        radiusMeters: (json['radius_meters'] as num?)?.toDouble() ?? 300,
        parkId: json['park_id']?.toString(),
        state: json['state'] as String?,
        oneShot: (json['one_shot'] ?? true) as bool,
      );
}
