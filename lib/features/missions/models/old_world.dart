/// The historical/story experience unlocked by a QR scan (`old_worlds`,
/// migration 0061).
class OldWorldCharacter {
  const OldWorldCharacter({required this.name, this.description, this.imageUrl});
  final String name;
  final String? description;
  final String? imageUrl;

  factory OldWorldCharacter.fromJson(Map<String, dynamic> j) => OldWorldCharacter(
        name: (j['name'] ?? '') as String,
        description: j['description'] as String?,
        imageUrl: j['image_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'image_url': imageUrl,
      };
}

class OldWorld {
  const OldWorld({
    required this.id,
    required this.title,
    this.historicalPeriod,
    this.isFictional = true,
    this.narrationText,
    this.narrationAudioUrl,
    this.heroImageUrl,
    this.historicalMapImageUrl,
    this.narratorName,
    this.characters = const [],
    this.clueText,
    this.nextStopId,
    this.voiceId,
    this.characterId,
    this.characterVideoUrl,
    this.revealsFactKeys = const [],
    this.stopId,
    this.nextObjectiveText,
    this.isClue = false,
    this.clueType,
    this.clueImageUrl,
    this.unlocksMapPieceId,
  });

  final String id;
  final String title;
  final String? historicalPeriod;

  /// Free-text voice fallback, used only when [characterId] is null.
  final String? voiceId;

  /// The [MissionCharacter] narrating this Old World reveal. When set, its
  /// name/voice are used instead of [narratorName]/[voiceId] — the same
  /// CHARACTER -> VOICE ID rule every other scene type follows. Distinct
  /// from [characters], which is just a descriptive cast list with no voice.
  final String? characterId;

  /// Named [MissionFact.key]s this Old World reveals when its narration
  /// plays — same mechanism as [MissionTravelStory.revealsFactKeys].
  final List<String> revealsFactKeys;

  /// Avatar video (HeyGen) for the character appearing at this reveal —
  /// "a NEW CHARACTER APPEARS," not just another narrated info page. Null
  /// falls back to the character's static image + audio-only narration.
  final String? characterVideoUrl;
  bool get hasCharacterVideo => (characterVideoUrl ?? '').trim().isNotEmpty;

  /// Direct back-reference to the [MissionStop] this Old World belongs to
  /// — needed to look up a stop-level "test of wits" question
  /// ([MissionPuzzle] with a matching `stop_id`) after the player just
  /// completed THIS stop, since by the time this reveal is on screen
  /// `ActiveMissionState.currentStop` has already advanced to the next one.
  final String? stopId;

  /// "YOUR NEXT OBJECTIVE" — a short, non-spoiler teaser about what's
  /// ahead, shown once this chapter (and any test-of-wits question)
  /// finishes, before the journey map opens for the next stop.
  final String? nextObjectiveText;

  /// Whether this reveal also appears in the Treasure Map's "Clues Found"
  /// list (see `treasureMapProvider`) — "found" once this row's [id] is in
  /// `MissionProgress.unlockedOldWorldIds`, already written the instant a
  /// QR scan resolves to this Old World.
  final bool isClue;

  /// image | audio | text | video | riddle | map_fragment | character_message.
  final String? clueType;

  /// Image clues (and the map-fragment preview) only.
  final String? clueImageUrl;

  /// The `mission_map_pieces.id` this clue unlocks, if any.
  final String? unlocksMapPieceId;

  /// Defaults to true deliberately — content must be explicitly marked
  /// verified-historical by an admin, never accidentally presented as real
  /// (spec: "Do not fabricate historical facts and present them as real").
  final bool isFictional;
  final String? narrationText;
  final String? narrationAudioUrl;
  final String? heroImageUrl;
  final String? historicalMapImageUrl;
  final String? narratorName;
  final List<OldWorldCharacter> characters;
  final String? clueText;
  final String? nextStopId;

  bool get hasClue => (clueText ?? '').trim().isNotEmpty;

  factory OldWorld.fromJson(Map<String, dynamic> j) => OldWorld(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '') as String,
        historicalPeriod: j['historical_period'] as String?,
        isFictional: (j['is_fictional'] ?? true) as bool,
        narrationText: j['narration_text'] as String?,
        narrationAudioUrl: j['narration_audio_url'] as String?,
        heroImageUrl: j['hero_image_url'] as String?,
        historicalMapImageUrl: j['historical_map_image_url'] as String?,
        narratorName: j['narrator_name'] as String?,
        characters: j['characters'] is List
            ? (j['characters'] as List)
                .whereType<Map>()
                .map((m) => OldWorldCharacter.fromJson(m.cast<String, dynamic>()))
                .toList()
            : const [],
        clueText: j['clue_text'] as String?,
        nextStopId: j['next_stop_id']?.toString(),
        voiceId: j['voice_id'] as String?,
        characterId: j['character_id']?.toString(),
        characterVideoUrl: j['character_video_url'] as String?,
        stopId: j['stop_id']?.toString(),
        nextObjectiveText: j['next_objective_text'] as String?,
        isClue: (j['is_clue'] ?? false) as bool,
        clueType: j['clue_type'] as String?,
        clueImageUrl: j['clue_image_url'] as String?,
        unlocksMapPieceId: j['unlocks_map_piece_id']?.toString(),
        revealsFactKeys: j['reveals_fact_keys'] is List
            ? (j['reveals_fact_keys'] as List).map((e) => e.toString()).toList()
            : const [],
      );

  Map<String, dynamic> toWrite() => {
        'title': title,
        'historical_period': historicalPeriod,
        'is_fictional': isFictional,
        'narration_text': narrationText,
        'narration_audio_url': narrationAudioUrl,
        'hero_image_url': heroImageUrl,
        'historical_map_image_url': historicalMapImageUrl,
        'narrator_name': narratorName,
        'characters': characters.map((c) => c.toJson()).toList(),
        'clue_text': clueText,
        'next_stop_id': nextStopId,
        'voice_id': voiceId,
        'character_id': characterId,
        'character_video_url': characterVideoUrl,
        'stop_id': stopId,
        'next_objective_text': nextObjectiveText,
        'is_clue': isClue,
        'clue_type': clueType,
        'clue_image_url': clueImageUrl,
        'unlocks_map_piece_id': unlocksMapPieceId,
        'reveals_fact_keys': revealsFactKeys,
      };
}
