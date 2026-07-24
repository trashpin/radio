import 'package:explorer_os_mobile/core/data/model.dart';

/// Per-station configuration that tunes the engine's scheduling decisions.
///
/// Read-only backend content. Instead of hardcoding cadences, each station
/// carries its own rules — how often to play a station identification, a
/// scheduled announcement, or a story narration, and whether ambient audio is
/// allowed. The schedulers ([StoryScheduler], [AnnouncementScheduler],
/// [StationManager]) read these to decide timing, so behavior is data-driven.
class StationRule implements Model {
  const StationRule({
    required this.id,
    required this.stationId,
    this.stationIdEveryTracks = 5,
    this.announcementEveryTracks = 4,
    this.storyEveryTracks = 3,
    this.allowAmbient = true,
    this.shuffleMusic = true,
  });

  @override
  final String id;
  final String stationId;

  /// Play a station identification after this many music tracks.
  final int stationIdEveryTracks;

  /// Play a scheduled announcement after this many music tracks.
  final int announcementEveryTracks;

  /// Insert a story narration after this many music tracks.
  final int storyEveryTracks;

  final bool allowAmbient;
  final bool shuffleMusic;

  factory StationRule.fromJson(Json json) => StationRule(
        id: json['id']?.toString() ?? '',
        stationId: json['station_id']?.toString() ?? '',
        stationIdEveryTracks:
            (json['station_id_every_tracks'] as num?)?.toInt() ?? 5,
        announcementEveryTracks:
            (json['announcement_every_tracks'] as num?)?.toInt() ?? 4,
        storyEveryTracks: (json['story_every_tracks'] as num?)?.toInt() ?? 3,
        allowAmbient: (json['allow_ambient'] ?? true) as bool,
        shuffleMusic: (json['shuffle_music'] ?? true) as bool,
      );
}
