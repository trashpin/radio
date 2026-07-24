import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';

/// Severity of a [SafetyAlert], which maps to a priority tier.
enum SafetyAlertSeverity { warning, critical, emergency }

/// A safety alert segment (weather hazard, trail closure, emergency broadcast).
///
/// Highest-impact spoken content: it interrupts music and resumes it after.
/// [toSegment] maps severity → the correct priority/type so `emergency` alerts
/// win over everything.
class SafetyAlert implements Model {
  const SafetyAlert({
    required this.id,
    required this.title,
    this.severity = SafetyAlertSeverity.warning,
    this.message,
    this.audioUrl,
    this.durationSeconds,
  });

  @override
  final String id;
  final String title;
  final SafetyAlertSeverity severity;
  final String? message;
  final String? audioUrl;
  final int? durationSeconds;

  factory SafetyAlert.fromJson(Json json) => SafetyAlert(
        id: json['id']?.toString() ?? '',
        title: (json['title'] ?? 'Safety alert') as String,
        severity: SafetyAlertSeverity.values.firstWhere(
          (s) => s.name == json['severity'],
          orElse: () => SafetyAlertSeverity.warning,
        ),
        message: json['message'] as String?,
        audioUrl: json['audio_url'] as String?,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      );

  AudioSegment toSegment() {
    final isEmergency = severity == SafetyAlertSeverity.emergency;
    return AudioSegment(
      id: 'safety:$id',
      title: title,
      type: isEmergency
          ? AudioSegmentType.emergencyBroadcast
          : AudioSegmentType.safetyWarning,
      priority: isEmergency
          ? PlaybackPriority.emergencyAlert
          : PlaybackPriority.safetyWarning,
      duration: Duration(seconds: durationSeconds ?? 0),
      audioUrl: audioUrl,
      interruptible: false,
      resumeAfter: true,
    );
  }
}
