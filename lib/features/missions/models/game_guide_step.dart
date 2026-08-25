/// One tappable detail in a `tutorial_observation` step's sample photo —
/// the Guide's response when the player picks THIS detail (spec: "WHAT DO
/// YOU NOTICE? ... Allow the player to tap a visual detail"). Kept as a
/// simple label + response pair (not pixel hotspots) — deliberately the
/// smallest version that satisfies "tap a visual detail."
class GuideDetailOption {
  const GuideDetailOption({required this.label, required this.response});
  final String label;
  final String response;

  factory GuideDetailOption.fromJson(Map<String, dynamic> j) => GuideDetailOption(
        label: (j['label'] ?? '') as String,
        response: (j['response'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {'label': label, 'response': response};
}

/// One beat of THE GUIDE's permanent, game-wide content (`game_guide_steps`)
/// — deliberately NOT a `mission_story_steps` row (that table requires a
/// mission_id; the Guide belongs to no mission) but column-compatible with
/// it wherever they overlap, so the same `heygen-avatar` edge function
/// generates video for either via a `table` parameter. See
/// `GuideIntroScreen` for how these play in sequence: one `introduction`,
/// several `tutorial_message`, one `tutorial_observation`.
class GameGuideStep {
  const GameGuideStep({
    required this.id,
    this.characterId,
    this.stepOrder = 0,
    this.stepType = kGuideStepTutorialMessage,
    required this.title,
    this.script,
    this.audioUrl,
    this.avatarVideoUrl,
    this.heygenVideoId,
    this.productionStatus = kGuideStatusDraft,
    this.sampleImageUrl,
    this.detailOptions = const [],
    this.active = true,
  });

  final String id;

  /// Null resolves to "the active local_guide character" at read time —
  /// almost every step shares the one Guide, so this is rarely set per-step.
  final String? characterId;
  final int stepOrder;
  final String stepType;

  /// Admin-facing label only, never shown to players.
  final String title;
  final String? script;
  final String? audioUrl;
  final String? avatarVideoUrl;
  final String? heygenVideoId;
  final String productionStatus;

  /// `tutorial_observation` only — the "WHAT DO YOU NOTICE?" sample photo.
  final String? sampleImageUrl;

  /// `tutorial_observation` only.
  final List<GuideDetailOption> detailOptions;
  final bool active;

  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
  bool get hasAvatarVideo => (avatarVideoUrl ?? '').trim().isNotEmpty;

  factory GameGuideStep.fromJson(Map<String, dynamic> j) => GameGuideStep(
        id: (j['id'] ?? '').toString(),
        characterId: j['character_id']?.toString(),
        stepOrder: (j['step_order'] as num?)?.toInt() ?? 0,
        stepType: (j['step_type'] ?? kGuideStepTutorialMessage) as String,
        title: (j['title'] ?? '') as String,
        script: j['script'] as String?,
        audioUrl: j['audio_url'] as String?,
        avatarVideoUrl: j['avatar_video_url'] as String?,
        heygenVideoId: j['heygen_video_id'] as String?,
        productionStatus: (j['production_status'] ?? kGuideStatusDraft) as String,
        sampleImageUrl: j['sample_image_url'] as String?,
        detailOptions: j['detail_options'] is List
            ? (j['detail_options'] as List)
                .whereType<Map>()
                .map((m) => GuideDetailOption.fromJson(m.cast<String, dynamic>()))
                .toList()
            : const [],
        active: (j['active'] ?? true) as bool,
      );

  Map<String, dynamic> toWrite() => {
        'character_id': characterId,
        'step_order': stepOrder,
        'step_type': stepType,
        'title': title,
        'script': script,
        'audio_url': audioUrl,
        'avatar_video_url': avatarVideoUrl,
        'heygen_video_id': heygenVideoId,
        'production_status': productionStatus,
        'sample_image_url': sampleImageUrl,
        'detail_options': detailOptions.map((d) => d.toJson()).toList(),
        'active': active,
      };
}

// ── step_type ────────────────────────────────────────────────────────────
const kGuideStepIntroduction = 'introduction';
const kGuideStepTutorialMessage = 'tutorial_message';
const kGuideStepTutorialObservation = 'tutorial_observation';

const List<String> kGuideStepTypes = [
  kGuideStepIntroduction,
  kGuideStepTutorialMessage,
  kGuideStepTutorialObservation,
];

// ── production_status — same vocabulary as mission_story_steps ────────────
const kGuideStatusDraft = 'draft';
const kGuideStatusScriptApproved = 'script_approved';
const kGuideStatusAudioGenerated = 'audio_generated';
const kGuideStatusVideoGenerated = 'video_generated';
const kGuideStatusReady = 'ready';
const kGuideStatusPublished = 'published';
