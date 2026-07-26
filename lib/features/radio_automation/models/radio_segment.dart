import 'package:flutter/material.dart';

/// Every playable non-music radio asset in the automation library.
enum SegmentCategory {
  djBanter('DJ_BANTER', 'DJ Banter', Icons.mic_rounded),
  songIntro('SONG_INTRO', 'Song Intro', Icons.play_circle_rounded),
  songOutro('SONG_OUTRO', 'Song Outro', Icons.stop_circle_rounded),
  stationId('STATION_ID', 'Station ID', Icons.radio_rounded),
  promo('PROMO', 'Promotion', Icons.campaign_rounded),
  weather('WEATHER', 'Weather', Icons.cloud_rounded),
  safety('SAFETY', 'Safety', Icons.health_and_safety_rounded),
  gpsTransition('GPS_TRANSITION', 'GPS Transition', Icons.navigation_rounded),
  wildlifeIntro('WILDLIFE_INTRO', 'Wildlife Intro', Icons.pets_rounded);

  const SegmentCategory(this.dbValue, this.label, this.icon);
  final String dbValue;
  final String label;
  final IconData icon;

  static SegmentCategory fromDb(String? v) => SegmentCategory.values.firstWhere(
        (e) => e.dbValue == v,
        orElse: () => SegmentCategory.djBanter,
      );
}

/// A saved radio segment (mirrors the `radio_segments` table).
class RadioSegment {
  const RadioSegment({
    required this.id,
    required this.title,
    required this.category,
    required this.station,
    this.parkId,
    this.voice,
    this.voiceId,
    this.songId,
    this.script,
    this.audioUrl,
    this.duration,
    this.generatedByAi = true,
    this.published = false,
    this.playCount = 0,
    this.lastPlayed,
    this.createdAt,
  });

  final String id;
  final String title;
  final SegmentCategory category;
  final String station; // all/country/rock/topHits/kids
  final String? parkId;
  final String? voice;
  final String? voiceId;
  final String? songId;
  final String? script;
  final String? audioUrl;
  final int? duration;
  final bool generatedByAi;
  final bool published;
  final int playCount;
  final DateTime? lastPlayed;
  final DateTime? createdAt;

  bool get hasAudio => (audioUrl ?? '').isNotEmpty;

  factory RadioSegment.fromJson(Map<String, dynamic> j) => RadioSegment(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? 'Untitled') as String,
        category: SegmentCategory.fromDb(j['category'] as String?),
        station: (j['station'] ?? 'all') as String,
        parkId: j['park_id'] as String?,
        voice: j['voice'] as String?,
        voiceId: j['voice_id'] as String?,
        songId: j['song_id'] as String?,
        script: j['script'] as String?,
        audioUrl: j['audio_url'] as String?,
        duration: (j['duration'] as num?)?.toInt(),
        generatedByAi: (j['generated_by_ai'] ?? true) as bool,
        published: (j['published'] ?? false) as bool,
        playCount: (j['play_count'] as num?)?.toInt() ?? 0,
        lastPlayed: DateTime.tryParse((j['last_played'] ?? '') as String? ?? ''),
        createdAt: DateTime.tryParse((j['created_at'] ?? '') as String? ?? ''),
      );

  /// Payload for insert/update (omits server-managed fields).
  Map<String, dynamic> toInsert() => {
        'title': title,
        'category': category.dbValue,
        'station': station,
        if (parkId != null) 'park_id': parkId,
        if (voice != null) 'voice': voice,
        if (voiceId != null) 'voice_id': voiceId,
        if (songId != null) 'song_id': songId,
        if (script != null) 'script': script,
        if (audioUrl != null) 'audio_url': audioUrl,
        if (duration != null) 'duration': duration,
        'generated_by_ai': generatedByAi,
        'published': published,
      };
}
