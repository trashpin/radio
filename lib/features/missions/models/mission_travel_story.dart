/// A distance-triggered narration on the way to a [MissionStop]
/// (`mission_travel_stories`, migration 0061). TRAVEL STORY and APPROACH
/// STORY (spec Phase 2/3) share this one shape — "at distance X from the
/// target stop, play narration Y" — distinguished only by [triggerType],
/// since a second near-identical table would just be a duplicate.
class MissionTravelStory {
  const MissionTravelStory({
    required this.id,
    required this.missionId,
    required this.stopId,
    this.triggerType = 'travel',
    required this.triggerDistanceMeters,
    required this.text,
    this.audioUrl,
    this.priority = 0,
    this.playOnce = true,
    this.sortOrder = 0,
    this.speakerName,
    this.voiceId,
    this.characterId,
    this.revealsFactKeys = const [],
    this.isClue = false,
    this.clueType,
    this.clueImageUrl,
    this.unlocksMapPieceId,
  });

  final String id;
  final String missionId;
  final String stopId;

  /// 'travel' (informational, further out) | 'approach' (anticipation-
  /// building, close in) — free text, not a fixed enum, so a future mission
  /// type can introduce a new beat without a migration.
  final String triggerType;
  final double triggerDistanceMeters;
  final String text;
  final String? audioUrl;
  final int priority;
  final bool playOnce;
  final int sortOrder;

  /// Who's speaking this beat (e.g. "Thomas", "Historian", "Narrator") —
  /// free-text fallback for content with no character record; optional,
  /// null reads as an unattributed narrator line. Ignored when
  /// [characterId] is set — the character's own name is used instead.
  final String? speakerName;

  /// An optional ElevenLabs voice override for this speaker, used only when
  /// [characterId] is null. Null falls back to the shared global default
  /// voice, exactly as every other narration in this app already does.
  final String? voiceId;

  /// The [MissionCharacter] speaking this beat. When set, its name and
  /// voice_id are used automatically — [speakerName]/[voiceId] are never
  /// consulted (see [ActiveMissionController]'s character resolution). This
  /// is the CHARACTER -> VOICE ID rule: a voice is never re-picked per scene.
  final String? characterId;

  /// Named [MissionFact.key]s this beat reveals when played — the player
  /// may not know why yet; a later [MissionPuzzle] may ask about one of
  /// them. Never inferred automatically; an admin tags these explicitly.
  final List<String> revealsFactKeys;

  /// Whether this beat also appears in the Treasure Map's "Clues Found"
  /// list (see `treasureMapProvider`) — "found" once this row's [id] is in
  /// `MissionProgress.firedContentIds`, which `ActiveMissionController`
  /// already writes the instant this story plays.
  final bool isClue;

  /// image | audio | text | video | riddle | map_fragment | character_message.
  final String? clueType;

  /// Image clues (and the map-fragment preview) only.
  final String? clueImageUrl;

  /// The `mission_map_pieces.id` this clue unlocks, if any.
  final String? unlocksMapPieceId;

  bool get isApproach => triggerType == 'approach';

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
  static List<String> _strs(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  factory MissionTravelStory.fromJson(Map<String, dynamic> j) => MissionTravelStory(
        id: (j['id'] ?? '').toString(),
        missionId: (j['mission_id'] ?? '').toString(),
        stopId: (j['stop_id'] ?? '').toString(),
        triggerType: (j['trigger_type'] ?? 'travel') as String,
        triggerDistanceMeters: _d(j['trigger_distance_meters']),
        text: (j['text'] ?? '') as String,
        audioUrl: j['audio_url'] as String?,
        priority: (j['priority'] as num?)?.toInt() ?? 0,
        playOnce: (j['play_once'] ?? true) as bool,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        speakerName: j['speaker_name'] as String?,
        voiceId: j['voice_id'] as String?,
        characterId: j['character_id']?.toString(),
        revealsFactKeys: _strs(j['reveals_fact_keys']),
        isClue: (j['is_clue'] ?? false) as bool,
        clueType: j['clue_type'] as String?,
        clueImageUrl: j['clue_image_url'] as String?,
        unlocksMapPieceId: j['unlocks_map_piece_id']?.toString(),
      );

  Map<String, dynamic> toWrite() => {
        'mission_id': missionId,
        'stop_id': stopId,
        'trigger_type': triggerType,
        'trigger_distance_meters': triggerDistanceMeters,
        'text': text,
        'audio_url': audioUrl,
        'priority': priority,
        'play_once': playOnce,
        'sort_order': sortOrder,
        'speaker_name': speakerName,
        'voice_id': voiceId,
        'character_id': characterId,
        'reveals_fact_keys': revealsFactKeys,
        'is_clue': isClue,
        'clue_type': clueType,
        'clue_image_url': clueImageUrl,
        'unlocks_map_piece_id': unlocksMapPieceId,
      };
}
