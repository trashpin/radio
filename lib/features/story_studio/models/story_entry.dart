import 'dart:math';

import 'package:explorer_os_mobile/features/story_studio/models/story_category.dart';

/// One AI-produced, GPS-triggered story (mirrors `story_library`).
class StoryEntry {
  const StoryEntry({
    required this.id,
    required this.title,
    required this.category,
    this.parkId,
    this.location,
    this.variation,
    this.collection,
    this.gpsZoneId,
    this.latitude,
    this.longitude,
    this.triggerRadiusM = 150,
    this.transcript,
    this.audioUrl,
    this.voice,
    this.voiceId,
    this.duration,
    this.audience = 'general',
    this.narrationStyle = 'ranger',
    this.status = StoryStatus.draft,
    this.approved = false,
    this.published = false,
    this.playCount = 0,
    this.lastPlayed,
    this.versionNumber = 1,
    this.createdAt,
  });

  final String id;
  final String title;
  final StoryCategory category;
  final String? parkId;
  final String? location;
  final String? variation;
  final String? collection;
  final String? gpsZoneId;
  final double? latitude;
  final double? longitude;
  final int triggerRadiusM;
  final String? transcript;
  final String? audioUrl;
  final String? voice;
  final String? voiceId;
  final int? duration;
  final String audience;
  final String narrationStyle;
  final StoryStatus status;
  final bool approved;
  final bool published;
  final int playCount;
  final DateTime? lastPlayed;
  final int versionNumber;
  final DateTime? createdAt;

  bool get hasAudio => (audioUrl ?? '').isNotEmpty;
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Playable at a visitor's location: published, has audio + coordinates.
  bool get playable => published && hasAudio && hasCoordinates;

  factory StoryEntry.fromJson(Map<String, dynamic> j) {
    double? d(dynamic v) => v is num ? v.toDouble() : null;
    return StoryEntry(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? 'Untitled') as String,
      category: StoryCategory.fromDb(j['category'] as String?),
      parkId: j['park_id'] as String?,
      location: j['location'] as String?,
      variation: j['variation'] as String?,
      collection: j['collection'] as String?,
      gpsZoneId: j['gps_zone_id'] as String?,
      latitude: d(j['latitude']),
      longitude: d(j['longitude']),
      triggerRadiusM: (j['trigger_radius_m'] as num?)?.toInt() ?? 150,
      transcript: j['transcript'] as String?,
      audioUrl: j['audio_url'] as String?,
      voice: j['voice'] as String?,
      voiceId: j['voice_id'] as String?,
      duration: (j['duration'] as num?)?.toInt(),
      audience: (j['audience'] ?? 'general') as String,
      narrationStyle: (j['narration_style'] ?? 'ranger') as String,
      status: StoryStatus.fromDb(j['status'] as String?),
      approved: (j['approved'] ?? false) as bool,
      published: (j['published'] ?? false) as bool,
      playCount: (j['play_count'] as num?)?.toInt() ?? 0,
      lastPlayed: DateTime.tryParse((j['last_played'] ?? '') as String? ?? ''),
      versionNumber: (j['version_number'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.tryParse((j['created_at'] ?? '') as String? ?? ''),
    );
  }

  Map<String, dynamic> toInsert() => {
        'title': title,
        'category': category.dbValue,
        if (parkId != null) 'park_id': parkId,
        if (location != null) 'location': location,
        if (variation != null) 'variation': variation,
        if (collection != null) 'collection': collection,
        if (gpsZoneId != null) 'gps_zone_id': gpsZoneId,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'trigger_radius_m': triggerRadiusM,
        if (transcript != null) 'transcript': transcript,
        if (audioUrl != null) 'audio_url': audioUrl,
        if (voice != null) 'voice': voice,
        if (voiceId != null) 'voice_id': voiceId,
        if (duration != null) 'duration': duration,
        'audience': audience,
        'narration_style': narrationStyle,
        'status': status.dbValue,
        'approved': approved,
        'published': published,
        'version_number': versionNumber,
      };
}

/// Distance in meters between two lat/lng points (haversine).
double metersBetween(double lat1, double lng1, double lat2, double lng2) {
  const earth = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLng / 2) *
          sin(dLng / 2);
  return earth * 2 * atan2(sqrt(h), sqrt(1 - h));
}
