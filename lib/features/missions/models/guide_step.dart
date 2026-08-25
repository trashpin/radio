/// One option in a `choice` Guide Step — a label plus a follow-up line.
/// Deliberately does NOT branch the route or mission graph; no such
/// infrastructure exists in this app.
class GuideChoiceOption {
  const GuideChoiceOption({required this.label, required this.response});
  final String label;
  final String response;

  factory GuideChoiceOption.fromJson(Map<String, dynamic> j) => GuideChoiceOption(
        label: (j['label'] ?? '') as String,
        response: (j['response'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {'label': label, 'response': response};
}

/// One beat in an adventure's Guide sequence (`guide_steps`, migration
/// 0077) — always delivered by THE GUIDE, distinct from
/// [MissionStoryStep] (the adventure characters' own story). See this
/// table's own migration comment for what it deliberately reuses instead
/// of duplicating (mission_puzzles for riddle/question hints,
/// mission_map_pieces for clue/map/discovery unlocks).
class GuideStep {
  const GuideStep({
    required this.id,
    required this.missionId,
    this.stopId,
    this.stepOrder = 0,
    this.contentType = kGuideContentTalk,
    required this.title,
    this.characterId,
    this.script,
    this.audioUrl,
    this.avatarVideoUrl,
    this.heygenVideoId,
    this.productionStatus = kGuideStepStatusDraft,
    this.imageUrl,
    this.puzzleId,
    this.unlocksMapPieceId,
    this.evidenceType,
    this.choiceOptions = const [],
    this.triggerType = kGuideTriggerManualDiscovery,
    this.triggerDistanceMeters,
    this.requiredPreviousGuideStepId,
    this.active = true,
  });

  final String id;
  final String missionId;
  final String? stopId;
  final int stepOrder;
  final String contentType;

  /// Admin-facing label only, never shown to players.
  final String title;

  /// Null resolves to "the active local_guide character" at read time.
  final String? characterId;
  final String? script;
  final String? audioUrl;
  final String? avatarVideoUrl;
  final String? heygenVideoId;
  final String productionStatus;

  /// image | inspect content types.
  final String? imageUrl;

  /// riddle | question content types — an existing `mission_puzzles` row.
  final String? puzzleId;

  /// clue | map | discovery content types.
  final String? unlocksMapPieceId;

  /// Non-null marks this step as HISTORICAL EVIDENCE delivered by
  /// [characterId] (an adventure character, e.g. Amos Ritter) rather than
  /// THE GUIDE's own modern presentation — orthogonal to [contentType],
  /// which still decides which UI component renders it (video/audio/
  /// image). Drives the archived/period visual treatment.
  final String? evidenceType;

  /// choice content type only.
  final List<GuideChoiceOption> choiceOptions;

  final String triggerType;
  final double? triggerDistanceMeters;
  final String? requiredPreviousGuideStepId;
  final bool active;

  bool get hasAudio => (audioUrl ?? '').trim().isNotEmpty;
  bool get hasAvatarVideo => (avatarVideoUrl ?? '').trim().isNotEmpty;
  bool get isHistoricalEvidence => (evidenceType ?? '').trim().isNotEmpty;

  factory GuideStep.fromJson(Map<String, dynamic> j) => GuideStep(
        id: (j['id'] ?? '').toString(),
        missionId: (j['mission_id'] ?? '').toString(),
        stopId: j['stop_id']?.toString(),
        stepOrder: (j['step_order'] as num?)?.toInt() ?? 0,
        contentType: (j['content_type'] ?? kGuideContentTalk) as String,
        title: (j['title'] ?? '') as String,
        characterId: j['character_id']?.toString(),
        script: j['script'] as String?,
        audioUrl: j['audio_url'] as String?,
        avatarVideoUrl: j['avatar_video_url'] as String?,
        heygenVideoId: j['heygen_video_id'] as String?,
        productionStatus: (j['production_status'] ?? kGuideStepStatusDraft) as String,
        imageUrl: j['image_url'] as String?,
        puzzleId: j['puzzle_id']?.toString(),
        unlocksMapPieceId: j['unlocks_map_piece_id']?.toString(),
        evidenceType: j['evidence_type'] as String?,
        choiceOptions: j['choice_options'] is List
            ? (j['choice_options'] as List)
                .whereType<Map>()
                .map((m) => GuideChoiceOption.fromJson(m.cast<String, dynamic>()))
                .toList()
            : const [],
        triggerType: (j['trigger_type'] ?? kGuideTriggerManualDiscovery) as String,
        triggerDistanceMeters: (j['trigger_distance_meters'] as num?)?.toDouble(),
        requiredPreviousGuideStepId: j['required_previous_guide_step_id']?.toString(),
        active: (j['active'] ?? true) as bool,
      );

  Map<String, dynamic> toWrite() => {
        'mission_id': missionId,
        'stop_id': stopId,
        'step_order': stepOrder,
        'content_type': contentType,
        'title': title,
        'character_id': characterId,
        'script': script,
        'audio_url': audioUrl,
        'avatar_video_url': avatarVideoUrl,
        'heygen_video_id': heygenVideoId,
        'production_status': productionStatus,
        'image_url': imageUrl,
        'puzzle_id': puzzleId,
        'unlocks_map_piece_id': unlocksMapPieceId,
        'evidence_type': evidenceType,
        'choice_options': choiceOptions.map((c) => c.toJson()).toList(),
        'trigger_type': triggerType,
        'trigger_distance_meters': triggerDistanceMeters,
        'required_previous_guide_step_id': requiredPreviousGuideStepId,
        'active': active,
      };
}

// ── content_type ─────────────────────────────────────────────────────────
const kGuideContentTalk = 'talk';
const kGuideContentImage = 'image';
const kGuideContentAudio = 'audio';
const kGuideContentVideo = 'video';
const kGuideContentPonder = 'ponder';
const kGuideContentRiddle = 'riddle';
const kGuideContentQuestion = 'question';
const kGuideContentClue = 'clue';
const kGuideContentMap = 'map';
const kGuideContentInspect = 'inspect';
const kGuideContentChoice = 'choice';
const kGuideContentDiscovery = 'discovery';

const List<String> kGuideContentTypes = [
  kGuideContentTalk,
  kGuideContentImage,
  kGuideContentAudio,
  kGuideContentVideo,
  kGuideContentPonder,
  kGuideContentRiddle,
  kGuideContentQuestion,
  kGuideContentClue,
  kGuideContentMap,
  kGuideContentInspect,
  kGuideContentChoice,
  kGuideContentDiscovery,
];

// ── trigger_type ─────────────────────────────────────────────────────────
const kGuideTriggerMissionStart = 'mission_start';
const kGuideTriggerDistanceFromDestination = 'distance_from_destination';
const kGuideTriggerArrival = 'arrival';
const kGuideTriggerQrScan = 'qr_scan';
const kGuideTriggerManualDiscovery = 'manual_discovery';
const kGuideTriggerPreviousStepComplete = 'previous_step_complete';
const kGuideTriggerMapPieceCollected = 'map_piece_collected';
const kGuideTriggerPuzzleSolved = 'puzzle_solved';

const List<String> kGuideTriggerTypes = [
  kGuideTriggerMissionStart,
  kGuideTriggerDistanceFromDestination,
  kGuideTriggerArrival,
  kGuideTriggerQrScan,
  kGuideTriggerManualDiscovery,
  kGuideTriggerPreviousStepComplete,
  kGuideTriggerMapPieceCollected,
  kGuideTriggerPuzzleSolved,
];

// ── production_status — same vocabulary as mission_story_steps ────────────
const kGuideStepStatusDraft = 'draft';
const kGuideStepStatusReady = 'ready';
const kGuideStepStatusVideoGenerated = 'video_generated';

// ── evidence_type — Historical Evidence, migration 0078 ────────────────────
const kEvidenceVideo = 'video';
const kEvidenceAudio = 'audio';
const kEvidencePhotograph = 'photograph';
const kEvidenceDocument = 'document';
const kEvidenceMap = 'map';
const kEvidenceObject = 'object';
const kEvidenceCharacterRecording = 'character_recording';

const List<String> kEvidenceTypes = [
  kEvidenceVideo,
  kEvidenceAudio,
  kEvidencePhotograph,
  kEvidenceDocument,
  kEvidenceMap,
  kEvidenceObject,
  kEvidenceCharacterRecording,
];

/// Player-facing label for an [GuideStep.evidenceType] value.
String evidenceTypeLabel(String type) => switch (type) {
      kEvidenceVideo => 'HISTORICAL FOOTAGE',
      kEvidenceAudio => 'ARCHIVED RECORDING',
      kEvidencePhotograph => 'HISTORICAL PHOTOGRAPH',
      kEvidenceDocument => 'HISTORICAL DOCUMENT',
      kEvidenceMap => 'HISTORICAL MAP FRAGMENT',
      kEvidenceObject => 'HISTORICAL OBJECT',
      kEvidenceCharacterRecording => 'CHARACTER RECORDING',
      _ => 'EVIDENCE',
    };
