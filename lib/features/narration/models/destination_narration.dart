import 'package:flutter/material.dart';

/// The 25 narration script types the studio generates per destination, each with
/// how many varied versions Explorer Radio should have to reduce repetition.
enum NarrationScriptType {
  arrival('arrival', 'Arrival', Icons.login_rounded, 3),
  quickIntro('quick_intro', 'Quick Introduction', Icons.bolt_rounded, 1),
  mainHistory('main_history', 'Main History', Icons.history_edu_rounded, 5),
  extendedHistory('extended_history', 'Extended History', Icons.menu_book_rounded, 1),
  thingsToNotice('things_to_notice', 'Things To Notice', Icons.visibility_rounded, 1),
  architecture('architecture', 'Architecture', Icons.account_balance_rounded, 1),
  wildlife('wildlife', 'Wildlife', Icons.pets_rounded, 3),
  plants('plants', 'Plants', Icons.local_florist_rounded, 1),
  trees('trees', 'Trees', Icons.park_rounded, 1),
  birds('birds', 'Birds', Icons.flutter_dash_rounded, 1),
  geology('geology', 'Geology', Icons.terrain_rounded, 1),
  photographyTips('photography_tips', 'Photography Tips', Icons.photo_camera_rounded, 1),
  funFacts('fun_facts', 'Fun Facts', Icons.lightbulb_rounded, 5),
  familyVersion('family_version', 'Family Version', Icons.family_restroom_rounded, 3),
  kidsVersion('kids_version', 'Kids Version', Icons.child_care_rounded, 3),
  accessibility('accessibility', 'Accessibility', Icons.accessible_rounded, 1),
  scenicHighlights('scenic_highlights', 'Scenic Highlights', Icons.landscape_rounded, 1),
  hiddenGems('hidden_gems', 'Hidden Gems', Icons.diamond_rounded, 1),
  nearbyAttractions('nearby_attractions', 'Nearby Attractions', Icons.near_me_rounded, 1),
  departure('departure', 'Departure', Icons.logout_rounded, 3),
  nightTour('night_tour', 'Night Tour', Icons.nightlight_rounded, 1),
  sunriseTour('sunrise_tour', 'Sunrise Tour', Icons.wb_twilight_rounded, 1),
  sunsetTour('sunset_tour', 'Sunset Tour', Icons.wb_sunny_rounded, 1),
  rainyDay('rainy_day', 'Rainy Day Version', Icons.umbrella_rounded, 1),
  emergencyInfo('emergency_info', 'Emergency Information', Icons.emergency_rounded, 1);

  const NarrationScriptType(this.dbValue, this.label, this.icon, this.variations);
  final String dbValue;
  final String label;
  final IconData icon;

  /// How many varied versions to generate (Explorer Radio randomizes them).
  final int variations;

  static NarrationScriptType? fromDb(String? v) {
    for (final t in values) {
      if (t.dbValue == v) return t;
    }
    return null;
  }
}

/// Lifecycle of a narration script.
enum NarrationStatus {
  draft('draft', 'Draft'),
  review('review', 'In review'),
  needsReview('needs_review', 'Needs review'),
  approved('approved', 'Approved'),
  published('published', 'Published');

  const NarrationStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static NarrationStatus fromDb(String? v) =>
      values.firstWhere((s) => s.dbValue == v, orElse: () => NarrationStatus.draft);
}

/// Suggested narrator voices (mapped to ElevenLabs voices in config).
enum NarratorVoice {
  ranger('National Park Ranger'),
  historian('Local Historian'),
  tourGuide('Friendly Tour Guide'),
  campfire('Campfire Storyteller'),
  kids('Kids Adventure Guide'),
  southern('Southern Storyteller');

  const NarratorVoice(this.label);
  final String label;
}

/// A narration script + audio for a destination (row in destination_narrations).
class DestinationNarration {
  const DestinationNarration({
    required this.id,
    required this.destinationId,
    required this.scriptType,
    this.title,
    this.script,
    this.audioUrl,
    this.voice,
    this.durationSeconds,
    this.status = NarrationStatus.draft,
    this.version = 1,
    this.variant = 1,
    this.language = 'en',
    this.wordCount = 0,
    this.speakingSeconds = 0,
    this.readabilityScore,
    this.factConfidence,
    this.duplicateScore,
    this.needsReview = false,
    this.aiModel,
    this.updatedAt,
    this.createdAt,
  });

  final String id;
  final String destinationId;
  final String scriptType;
  final String? title;
  final String? script;
  final String? audioUrl;
  final String? voice;
  final int? durationSeconds;
  final NarrationStatus status;
  final int version;
  final int variant;
  final String language;
  final int wordCount;
  final int speakingSeconds;
  final double? readabilityScore;
  final double? factConfidence;
  final double? duplicateScore;
  final bool needsReview;
  final String? aiModel;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  bool get hasAudio => (audioUrl ?? '').isNotEmpty;
  NarrationScriptType? get type => NarrationScriptType.fromDb(scriptType);

  factory DestinationNarration.fromJson(Map<String, dynamic> j) {
    int i(dynamic v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;
    double? d(dynamic v) => (v as num?)?.toDouble();
    DateTime? dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    return DestinationNarration(
      id: (j['id'] ?? '').toString(),
      destinationId: (j['destination_id'] ?? '').toString(),
      scriptType: (j['script_type'] ?? '') as String,
      title: j['title'] as String?,
      script: j['script'] as String?,
      audioUrl: j['audio_url'] as String?,
      voice: j['voice'] as String?,
      durationSeconds: (j['duration_seconds'] as num?)?.toInt(),
      status: NarrationStatus.fromDb(j['status'] as String?),
      version: i(j['version'], 1),
      variant: i(j['variant'], 1),
      language: (j['language'] ?? 'en') as String,
      wordCount: i(j['word_count']),
      speakingSeconds: i(j['speaking_seconds']),
      readabilityScore: d(j['readability_score']),
      factConfidence: d(j['fact_confidence']),
      duplicateScore: d(j['duplicate_score']),
      needsReview: (j['needs_review'] ?? false) as bool,
      aiModel: j['ai_model'] as String?,
      updatedAt: dt(j['updated_at']),
      createdAt: dt(j['created_at']),
    );
  }
}

/// Driving narration between two destinations (row in route_narrations).
class RouteNarration {
  const RouteNarration({
    required this.id,
    this.fromDestinationId,
    this.toDestinationId,
    this.routeName,
    this.distance,
    this.estimatedDriveTime,
    this.script,
    this.audioUrl,
    this.status = NarrationStatus.draft,
    this.wordCount = 0,
    this.needsReview = false,
  });

  final String id;
  final String? fromDestinationId;
  final String? toDestinationId;
  final String? routeName;
  final double? distance;
  final int? estimatedDriveTime;
  final String? script;
  final String? audioUrl;
  final NarrationStatus status;
  final int wordCount;
  final bool needsReview;

  factory RouteNarration.fromJson(Map<String, dynamic> j) => RouteNarration(
        id: (j['id'] ?? '').toString(),
        fromDestinationId: j['from_destination_id']?.toString(),
        toDestinationId: j['to_destination_id']?.toString(),
        routeName: j['route_name'] as String?,
        distance: (j['distance'] as num?)?.toDouble(),
        estimatedDriveTime: (j['estimated_drive_time'] as num?)?.toInt(),
        script: j['script'] as String?,
        audioUrl: j['audio_url'] as String?,
        status: NarrationStatus.fromDb(j['status'] as String?),
        wordCount: (j['word_count'] as num?)?.toInt() ?? 0,
        needsReview: (j['needs_review'] ?? false) as bool,
      );
}
