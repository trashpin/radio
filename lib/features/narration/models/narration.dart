import 'package:explorer_os_mobile/core/data/model.dart';
import 'package:explorer_os_mobile/features/narration/models/narration_type.dart';

/// A pre-generated narration for a content record (species, park, trail, …).
///
/// Scripts and audio are generated once during authoring and stored
/// permanently; the app just streams [audioUrl] for instant playback and never
/// calls AI at runtime.
class Narration implements Model {
  const Narration({
    required this.id,
    required this.contentId,
    required this.contentType,
    this.parkId,
    this.title,
    this.narrationType = NarrationType.standardRanger,
    this.voiceName,
    this.voiceId,
    this.script,
    this.audioUrl,
    this.duration,
    this.language = 'en',
    this.status = 'draft',
    this.approved = false,
    this.featured = false,
    this.createdAt,
    this.updatedAt,
  });

  @override
  final String id;
  final String contentId;
  final String contentType; // e.g. 'species', 'park', 'trail'
  final String? parkId;
  final String? title;
  final NarrationType narrationType;
  final String? voiceName;
  final String? voiceId;
  final String? script;
  final String? audioUrl;
  final int? duration; // seconds
  final String language;
  final String status; // draft | pending_review | published
  final bool approved;
  final bool featured;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;
  bool get hasScript => script != null && script!.trim().isNotEmpty;

  Narration copyWith({
    String? title,
    NarrationType? narrationType,
    String? script,
    String? audioUrl,
    int? duration,
    String? voiceName,
    String? voiceId,
    String? status,
    bool? approved,
    bool? featured,
  }) =>
      Narration(
        id: id,
        contentId: contentId,
        contentType: contentType,
        parkId: parkId,
        title: title ?? this.title,
        narrationType: narrationType ?? this.narrationType,
        voiceName: voiceName ?? this.voiceName,
        voiceId: voiceId ?? this.voiceId,
        script: script ?? this.script,
        audioUrl: audioUrl ?? this.audioUrl,
        duration: duration ?? this.duration,
        language: language,
        status: status ?? this.status,
        approved: approved ?? this.approved,
        featured: featured ?? this.featured,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  factory Narration.fromJson(Json json) => Narration(
        id: (json['id'] ?? '').toString(),
        contentId: (json['content_id'] ?? '').toString(),
        contentType: (json['content_type'] ?? '') as String,
        parkId: json['park_id']?.toString(),
        title: json['title'] as String?,
        narrationType: NarrationType.fromId(json['narration_type'] as String?),
        voiceName: json['voice_name'] as String?,
        voiceId: json['voice_id'] as String?,
        script: json['script'] as String?,
        audioUrl: json['audio_url'] as String?,
        duration: (json['duration'] as num?)?.toInt(),
        language: (json['language'] ?? 'en') as String,
        status: (json['status'] ?? 'draft') as String,
        approved: (json['approved'] ?? false) as bool,
        featured: (json['featured'] ?? false) as bool,
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      );

  /// For insert/update (omits id/timestamps so DB defaults apply).
  Json toJson() => {
        'content_id': contentId,
        'content_type': contentType,
        if (parkId != null) 'park_id': parkId,
        if (title != null) 'title': title,
        'narration_type': narrationType.id,
        if (voiceName != null) 'voice_name': voiceName,
        if (voiceId != null) 'voice_id': voiceId,
        if (script != null) 'script': script,
        if (audioUrl != null) 'audio_url': audioUrl,
        if (duration != null) 'duration': duration,
        'language': language,
        'status': status,
        'approved': approved,
        'featured': featured,
      };
}
