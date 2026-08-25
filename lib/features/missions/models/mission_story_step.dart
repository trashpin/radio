/// One beat in the Story Production System's authoring sequence
/// (`mission_story_steps`, migration 0066): MISSION INTRODUCTION -> TRAVEL
/// STORY -> APPROACH STORY -> ARRIVAL -> DISCOVERY -> QR -> OLD WORLD ->
/// CLUE -> FINAL REVEAL, in any order/mix an admin builds via the Story
/// Builder.
///
/// This is an AUTHORING/PRODUCTION record, not a second runtime trigger
/// system: [ActiveMissionController]/[MissionStoryEngine] never read this
/// table directly. Publishing a step (see `StoryStepPublisher`) writes its
/// script/audio/character into the matching existing runtime row
/// (missions/mission_stops/mission_travel_stories/old_worlds) -- those
/// tables stay the single source of truth the live GPS/mission player
/// actually reads, exactly as before this system existed.
class MissionStoryStep {
  const MissionStoryStep({
    required this.id,
    required this.missionId,
    this.stopId,
    this.stepOrder = 0,
    required this.title,
    this.stepType = kStepTypeTravelStory,
    this.characterId,
    this.script,
    this.presentationType = kPresentationAudioOnly,
    this.audioUrl,
    this.avatarVideoUrl,
    this.triggerType = kTriggerDistanceFromDestination,
    this.triggerDistanceMeters,
    this.qrPortalId,
    this.requiredPreviousStepId,
    this.clueText,
    this.questionText,
    this.answerText,
    this.xpReward = 0,
    this.nextStepId,
    this.productionStatus = kStatusDraft,
    this.active = true,
    this.publishedRowId,
    this.heygenVideoId,
    this.revealsFactKeys = const [],
    this.isClue = false,
    this.clueType,
    this.clueImageUrl,
    this.unlocksMapPieceId,
  });

  final String id;
  final String missionId;
  final String? stopId;
  final int stepOrder;
  final String title;
  final String stepType;
  final String? characterId;

  /// The editable narration text — script generation (if ever added) writes
  /// here, an admin edits it, and only THEN does Generate Voice speak it.
  final String? script;
  final String presentationType;
  final String? audioUrl;
  final String? avatarVideoUrl;
  final String triggerType;
  final double? triggerDistanceMeters;
  final String? qrPortalId;
  final String? requiredPreviousStepId;
  final String? clueText;
  final String? questionText;
  final String? answerText;
  final int xpReward;
  final String? nextStepId;
  final String productionStatus;
  final bool active;

  /// Which existing runtime row (today: a `mission_travel_stories.id`) this
  /// step last published into — republishing updates that row instead of
  /// creating a duplicate. Other step types update an existing row directly
  /// (a stop's arrival fields, its Old World, or the mission itself) and
  /// don't need this.
  final String? publishedRowId;

  /// The HeyGen render job id while an avatar video is processing — see
  /// `heygen-avatar` edge function. Non-null while a render is in flight or
  /// just finished; the UI uses this to know whether to offer "check
  /// status" instead of "generate avatar" again.
  final String? heygenVideoId;

  /// Named `mission_facts.key` values this step reveals when it plays —
  /// the "plant a detail early, pay it off later" mechanic. Published into
  /// `mission_travel_stories.reveals_fact_keys` or
  /// `old_worlds.reveals_fact_keys` depending on [stepType].
  final List<String> revealsFactKeys;

  /// Whether this step is also a Treasure Map discovery item — copied
  /// through onto the runtime row `StoryStepPublisher` writes into
  /// (`mission_travel_stories.is_clue` / `old_worlds.is_clue`), which is
  /// what the player-facing Treasure Map actually reads.
  final bool isClue;

  /// image | audio | text | video | riddle | map_fragment | character_message.
  final String? clueType;

  /// Image clues (and the map-fragment preview) only.
  final String? clueImageUrl;

  /// The `mission_map_pieces.id` this clue unlocks, if any.
  final String? unlocksMapPieceId;

  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
  bool get hasAvatarVideo => (avatarVideoUrl ?? '').trim().isNotEmpty;
  bool get needsAvatar => presentationType == kPresentationAvatarVideo;

  static double? _dOrNull(dynamic v) => (v as num?)?.toDouble();

  factory MissionStoryStep.fromJson(Map<String, dynamic> j) => MissionStoryStep(
        id: (j['id'] ?? '').toString(),
        missionId: (j['mission_id'] ?? '').toString(),
        stopId: j['stop_id']?.toString(),
        stepOrder: (j['step_order'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '') as String,
        stepType: (j['step_type'] ?? kStepTypeTravelStory) as String,
        characterId: j['character_id']?.toString(),
        script: j['script'] as String?,
        presentationType: (j['presentation_type'] ?? kPresentationAudioOnly) as String,
        audioUrl: j['audio_url'] as String?,
        avatarVideoUrl: j['avatar_video_url'] as String?,
        triggerType: (j['trigger_type'] ?? kTriggerDistanceFromDestination) as String,
        triggerDistanceMeters: _dOrNull(j['trigger_distance_meters']),
        qrPortalId: j['qr_portal_id']?.toString(),
        requiredPreviousStepId: j['required_previous_step_id']?.toString(),
        clueText: j['clue_text'] as String?,
        questionText: j['question_text'] as String?,
        answerText: j['answer_text'] as String?,
        xpReward: (j['xp_reward'] as num?)?.toInt() ?? 0,
        nextStepId: j['next_step_id']?.toString(),
        productionStatus: (j['production_status'] ?? kStatusDraft) as String,
        active: (j['active'] ?? true) as bool,
        publishedRowId: j['published_row_id']?.toString(),
        heygenVideoId: j['heygen_video_id'] as String?,
        revealsFactKeys: j['reveals_fact_keys'] is List
            ? (j['reveals_fact_keys'] as List).map((e) => e.toString()).toList()
            : const [],
        isClue: (j['is_clue'] ?? false) as bool,
        clueType: j['clue_type'] as String?,
        clueImageUrl: j['clue_image_url'] as String?,
        unlocksMapPieceId: j['unlocks_map_piece_id']?.toString(),
      );

  Map<String, dynamic> toWrite() => {
        'mission_id': missionId,
        'stop_id': stopId,
        'step_order': stepOrder,
        'title': title,
        'step_type': stepType,
        'character_id': characterId,
        'script': script,
        'presentation_type': presentationType,
        'audio_url': audioUrl,
        'avatar_video_url': avatarVideoUrl,
        'trigger_type': triggerType,
        'trigger_distance_meters': triggerDistanceMeters,
        'qr_portal_id': qrPortalId,
        'required_previous_step_id': requiredPreviousStepId,
        'clue_text': clueText,
        'question_text': questionText,
        'answer_text': answerText,
        'xp_reward': xpReward,
        'next_step_id': nextStepId,
        'production_status': productionStatus,
        'active': active,
        'published_row_id': publishedRowId,
        'heygen_video_id': heygenVideoId,
        'reveals_fact_keys': revealsFactKeys,
        'is_clue': isClue,
        'clue_type': clueType,
        'clue_image_url': clueImageUrl,
        'unlocks_map_piece_id': unlocksMapPieceId,
      };
}

// ── step_type ────────────────────────────────────────────────────────────
const kStepTypeMissionIntroduction = 'mission_introduction';
const kStepTypeTravelStory = 'travel_story';
const kStepTypeApproachStory = 'approach_story';
const kStepTypeArrival = 'arrival';
const kStepTypeDiscovery = 'discovery';
const kStepTypeQr = 'qr';
const kStepTypeOldWorld = 'old_world';
const kStepTypeClue = 'clue';
const kStepTypeFinalReveal = 'final_reveal';

const List<String> kMissionStoryStepTypes = [
  kStepTypeMissionIntroduction,
  kStepTypeTravelStory,
  kStepTypeApproachStory,
  kStepTypeArrival,
  kStepTypeDiscovery,
  kStepTypeQr,
  kStepTypeOldWorld,
  kStepTypeClue,
  kStepTypeFinalReveal,
];

// ── presentation_type ───────────────────────────────────────────────────
const kPresentationAudioOnly = 'audio_only';
const kPresentationAvatarVideo = 'avatar_video';
const kPresentationTextAudio = 'text_audio';

const List<String> kMissionStepPresentationTypes = [
  kPresentationAudioOnly,
  kPresentationAvatarVideo,
  kPresentationTextAudio,
];

// ── trigger_type ─────────────────────────────────────────────────────────
const kTriggerMissionStart = 'mission_start';
const kTriggerDistanceFromDestination = 'distance_from_destination';
const kTriggerApproach = 'approach';
const kTriggerArrival = 'arrival';
const kTriggerQrScan = 'qr_scan';
const kTriggerManualDiscovery = 'manual_discovery';
const kTriggerPreviousStepComplete = 'previous_step_complete';
const kTriggerMissionComplete = 'mission_complete';

const List<String> kMissionStepTriggerTypes = [
  kTriggerMissionStart,
  kTriggerDistanceFromDestination,
  kTriggerApproach,
  kTriggerArrival,
  kTriggerQrScan,
  kTriggerManualDiscovery,
  kTriggerPreviousStepComplete,
  kTriggerMissionComplete,
];

// ── production_status ───────────────────────────────────────────────────
const kStatusDraft = 'draft';
const kStatusScriptApproved = 'script_approved';
const kStatusAudioGenerated = 'audio_generated';
const kStatusVideoGenerated = 'video_generated';
const kStatusReady = 'ready';
const kStatusPublished = 'published';

const List<String> kMissionStepProductionStatuses = [
  kStatusDraft,
  kStatusScriptApproved,
  kStatusAudioGenerated,
  kStatusVideoGenerated,
  kStatusReady,
  kStatusPublished,
];
