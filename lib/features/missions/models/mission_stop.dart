/// A physical destination within a [Mission] (`mission_stops`, migration
/// 0061). Self-contained (own lat/lng/radius) so a mission-only POI never
/// requires first creating a general-purpose `locations` row, but
/// [locationId] can optionally link one for reuse of its existing
/// photos/description — and, longer-term, so the same physical place can be
/// shared across multiple missions.
class MissionStop {
  const MissionStop({
    required this.id,
    required this.missionId,
    required this.sequence,
    required this.title,
    this.locationId,
    required this.latitude,
    required this.longitude,
    this.arrivalRadiusMeters = 150,
    this.arrivalNarrationText,
    this.arrivalNarrationAudioUrl,
    this.requiresQr = true,
    this.qrPortalId,
    this.oldWorldId,
    this.nextStopId,
  });

  final String id;
  final String missionId;
  final int sequence;
  final String title;
  final String? locationId;
  final double latitude;
  final double longitude;
  final double arrivalRadiusMeters;
  final String? arrivalNarrationText;
  final String? arrivalNarrationAudioUrl;
  final bool requiresQr;
  final String? qrPortalId;
  final String? oldWorldId;
  final String? nextStopId;

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  factory MissionStop.fromJson(Map<String, dynamic> j) => MissionStop(
        id: (j['id'] ?? '').toString(),
        missionId: (j['mission_id'] ?? '').toString(),
        sequence: (j['sequence'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '') as String,
        locationId: j['location_id']?.toString(),
        latitude: _d(j['latitude']),
        longitude: _d(j['longitude']),
        arrivalRadiusMeters: (j['arrival_radius_meters'] as num?)?.toDouble() ?? 150,
        arrivalNarrationText: j['arrival_narration_text'] as String?,
        arrivalNarrationAudioUrl: j['arrival_narration_audio_url'] as String?,
        requiresQr: (j['requires_qr'] ?? true) as bool,
        qrPortalId: j['qr_portal_id']?.toString(),
        oldWorldId: j['old_world_id']?.toString(),
        nextStopId: j['next_stop_id']?.toString(),
      );

  Map<String, dynamic> toWrite() => {
        'mission_id': missionId,
        'sequence': sequence,
        'title': title,
        'location_id': locationId,
        'latitude': latitude,
        'longitude': longitude,
        'arrival_radius_meters': arrivalRadiusMeters,
        'arrival_narration_text': arrivalNarrationText,
        'arrival_narration_audio_url': arrivalNarrationAudioUrl,
        'requires_qr': requiresQr,
        'qr_portal_id': qrPortalId,
        'old_world_id': oldWorldId,
        'next_stop_id': nextStopId,
      };
}
