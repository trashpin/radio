import 'package:explorer_os_mobile/features/radio/models/announcement.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/shared/models/narration.dart';
import 'package:explorer_os_mobile/shared/models/song.dart';

/// The kind of content an [AudioSegment] represents.
enum AudioSegmentType {
  music,
  narration,
  announcement,
  stationIdentification,
  safetyWarning,
  emergencyAlert,
  gpsNarration,
  ambient,
}

/// A normalized, playable unit of audio — the ONLY thing the engine reasons
/// about.
///
/// Every source of sound (a [Song], a [Narration], an [Announcement], a safety
/// alert, a GPS trigger) is converted into an [AudioSegment] so the engine can
/// treat them uniformly: order them by [priority], decide whether one may
/// interrupt another ([interruptible]), and know whether to resume the
/// previous item afterwards ([resumeAfter]). The engine never plays these — it
/// only decides which one should play; a future audio backend consumes
/// [audioUrl].
class AudioSegment {
  const AudioSegment({
    required this.id,
    required this.title,
    required this.type,
    required this.priority,
    this.duration = Duration.zero,
    this.audioUrl,
    this.stationId,
    this.parkId,
    this.state,
    this.location,
    this.tags = const [],
    this.interruptible = true,
    this.resumeAfter = false,
  });

  final String id;
  final String title;
  final AudioSegmentType type;

  /// Where this item sits on the priority ladder (drives ordering + interrupts).
  final PlaybackPriority priority;
  final Duration duration;
  final String? audioUrl;

  /// Owning radio station (the `station` field from the spec).
  final String? stationId;

  /// Associated park (the `park` field).
  final String? parkId;

  /// Associated US state/region (the `state` field).
  final String? state;

  /// Geographic relevance (the `location` field) — reserved for GPS.
  final GeoPoint? location;
  final List<String> tags;

  /// Whether a higher-priority item is allowed to interrupt this one.
  final bool interruptible;

  /// Whether the engine should resume the previously-paused item after this one
  /// finishes (true for interruptions like alerts/narration/announcements).
  final bool resumeAfter;

  AudioSegment copyWith({PlaybackPriority? priority}) => AudioSegment(
        id: id,
        title: title,
        type: type,
        priority: priority ?? this.priority,
        duration: duration,
        audioUrl: audioUrl,
        stationId: stationId,
        parkId: parkId,
        state: state,
        location: location,
        tags: tags,
        interruptible: interruptible,
        resumeAfter: resumeAfter,
      );

  // --- Factories: map source content into normalized segments --------------

  /// Music track — the interruptible baseline the engine keeps coming back to.
  factory AudioSegment.fromSong(Song song, {String? parkId, String? state}) {
    return AudioSegment(
      id: 'song:${song.id}',
      title: song.title,
      type: AudioSegmentType.music,
      priority: PlaybackPriority.music,
      duration: Duration(seconds: song.durationSeconds ?? 0),
      audioUrl: song.audioUrl,
      stationId: song.stationId,
      parkId: parkId,
      state: state,
      interruptible: true,
      resumeAfter: false,
    );
  }

  /// Story narration — scheduled content that interrupts music and resumes it.
  factory AudioSegment.fromNarration(
    Narration narration, {
    PlaybackPriority priority = PlaybackPriority.scheduledAnnouncement,
    AudioSegmentType type = AudioSegmentType.narration,
    String? stationId,
    String? parkId,
    String? state,
    GeoPoint? location,
  }) {
    return AudioSegment(
      id: 'narration:${narration.id}',
      title: narration.title,
      type: type,
      priority: priority,
      duration: Duration(seconds: narration.durationSeconds ?? 0),
      audioUrl: narration.audioUrl,
      stationId: stationId,
      parkId: parkId,
      state: state,
      location: location,
      interruptible: false,
      resumeAfter: true,
    );
  }

  /// Scheduled announcement or station identification.
  factory AudioSegment.fromAnnouncement(Announcement announcement) {
    final isStationId =
        announcement.kind == AnnouncementKind.stationIdentification;
    return AudioSegment(
      id: 'announcement:${announcement.id}',
      title: announcement.title,
      type: isStationId
          ? AudioSegmentType.stationIdentification
          : AudioSegmentType.announcement,
      priority: isStationId
          ? PlaybackPriority.stationIdentification
          : PlaybackPriority.scheduledAnnouncement,
      duration: Duration(seconds: announcement.durationSeconds ?? 0),
      audioUrl: announcement.audioUrl,
      stationId: announcement.stationId,
      parkId: announcement.parkId,
      state: announcement.state,
      tags: announcement.tags,
      interruptible: false,
      resumeAfter: true,
    );
  }
}
