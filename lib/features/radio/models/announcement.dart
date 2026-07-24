import 'package:explorer_os_mobile/core/data/model.dart';

/// Distinguishes a general scheduled announcement from a station identification
/// ("You're listening to Explorer Radio…").
enum AnnouncementKind { scheduled, stationIdentification }

/// A scheduled spoken announcement or station identification.
///
/// Read-only backend content. The [AnnouncementScheduler] decides WHEN one of
/// these should be injected into the stream (based on [intervalMinutes] and the
/// station's rules); the engine then queues it at the appropriate priority.
class Announcement implements Model {
  const Announcement({
    required this.id,
    required this.title,
    this.kind = AnnouncementKind.scheduled,
    this.stationId,
    this.audioUrl,
    this.durationSeconds,
    this.intervalMinutes,
    this.parkId,
    this.state,
    this.tags = const [],
  });

  @override
  final String id;
  final String title;
  final AnnouncementKind kind;
  final String? stationId;
  final String? audioUrl;
  final int? durationSeconds;

  /// How often (minutes) this announcement is eligible to play.
  final int? intervalMinutes;
  final String? parkId;
  final String? state;
  final List<String> tags;

  factory Announcement.fromJson(Json json) => Announcement(
        id: json['id']?.toString() ?? '',
        title: (json['title'] ?? '') as String,
        kind: (json['kind'] == 'station_identification')
            ? AnnouncementKind.stationIdentification
            : AnnouncementKind.scheduled,
        stationId: json['station_id']?.toString(),
        audioUrl: json['audio_url'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        intervalMinutes: (json['interval_minutes'] as num?)?.toInt(),
        parkId: json['park_id']?.toString(),
        state: json['state'] as String?,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      );
}
