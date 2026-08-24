/// A complete Marion County Adventures adventure (`missions`, migration 0061).
class Mission {
  const Mission({
    required this.id,
    required this.title,
    this.description,
    this.category,
    this.difficulty,
    this.estimatedDurationMinutes,
    this.published = false,
    this.startingLocationId,
    this.openingNarrationText,
    this.openingNarrationAudioUrl,
    this.completionRewardXp = 0,
    this.completionBadge,
    this.missionBriefText,
    this.introCharacterName,
    this.introCharacterId,
    this.openingVideoUrl,
    this.finalRevealText,
    this.heroImageUrl,
    this.storyHook,
    this.imageClueText,
    this.finalRevealVideoUrl,
    this.realHistoryText,
  });

  final String id;
  final String title;
  final String? description;

  /// Free text, e.g. 'history', 'mystery', 'nature', 'wildlife', 'springs',
  /// 'treasure' — matches this app's existing free-text category convention
  /// (never a fixed enum) so new mission themes never need a migration.
  final String? category;

  /// Free text — 'easy' / 'adventure' / 'challenge' / 'master' are the
  /// suggested vocabulary, not an enforced enum (the scale is still
  /// evolving; see migration 0063).
  final String? difficulty;
  final int? estimatedDurationMinutes;
  final bool published;
  final String? startingLocationId;
  final String? openingNarrationText;
  final String? openingNarrationAudioUrl;
  final int completionRewardXp;
  final String? completionBadge;

  /// The "YOUR MISSION: find the journal, follow the trail..." paragraph
  /// shown on the Adventure Introduction screen, before any map/GPS/travel
  /// begins.
  final String? missionBriefText;

  /// Who speaks the adventure introduction (e.g. "Thomas", or a mystery
  /// narrator) — shown alongside [openingNarrationText]. Free-text fallback
  /// for content with no character record; [introCharacterId] takes priority
  /// when set (see [ActiveMissionController]'s character resolution).
  final String? introCharacterName;

  /// The [MissionCharacter] who speaks the Adventure Introduction. When set,
  /// its name/image/role/voice are used instead of [introCharacterName] and
  /// the opening narration's own voice.
  final String? introCharacterId;

  /// The character avatar video (HeyGen) shown at the top of the Adventure
  /// Introduction, before any map/GPS begins — "the first thing a player
  /// should hear and see." Published from a `mission_introduction`-type
  /// [MissionStoryStep]. Null falls back to the static character image +
  /// audio-only narration [MissionIntroScreen] already shows.
  final String? openingVideoUrl;

  bool get hasOpeningVideo => (openingVideoUrl ?? '').trim().isNotEmpty;

  /// "YOU SOLVED IT... you remembered the silver pocket watch..." — the
  /// explanation of how the clues connected, shown at mission completion.
  final String? finalRevealText;

  bool get hasOpeningNarration =>
      (openingNarrationText ?? '').trim().isNotEmpty ||
      (openingNarrationAudioUrl ?? '').trim().isNotEmpty;

  /// The Adventure Card / Mission Introduction's mystery artwork — NEVER a
  /// photo of an actual destination, never auto-derived from a location
  /// record. May contain a subtle, never-labeled visual clue a later story
  /// step references (see [imageClueText], admin-only).
  final String? heroImageUrl;
  bool get hasHeroImage => (heroImageUrl ?? '').trim().isNotEmpty;

  /// The short, curiosity-only teaser shown on the Adventure Card
  /// ("WHY SHOULD I CARE?", never "WHERE AM I GOING?"). Separate from
  /// [description] so it can be held to a strict no-spoiler rule.
  final String? storyHook;

  /// Admin-only authoring note: what [heroImageUrl] secretly hints at.
  /// Never rendered to the player anywhere in the app.
  final String? imageClueText;

  /// Avatar video (HeyGen) delivering the Final Reveal — mirrors
  /// [openingVideoUrl]'s role at the start of the adventure, so the same
  /// character can open AND close the story. Null falls back to
  /// [finalRevealText] shown as plain text.
  final String? finalRevealVideoUrl;
  bool get hasFinalRevealVideo => (finalRevealVideoUrl ?? '').trim().isNotEmpty;

  /// "THE REAL HISTORY" — a whole-adventure disclosure of what's verified,
  /// what source supports it, what was fictionalized, and why it matters.
  /// Separate from [finalRevealText] (the dramatic story reveal) and shown
  /// after it, clearly labeled, at Mission Complete.
  final String? realHistoryText;

  factory Mission.fromJson(Map<String, dynamic> j) => Mission(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '') as String,
        description: j['description'] as String?,
        category: j['category'] as String?,
        difficulty: j['difficulty'] as String?,
        estimatedDurationMinutes: (j['estimated_duration_minutes'] as num?)?.toInt(),
        published: (j['published'] ?? false) as bool,
        startingLocationId: j['starting_location_id']?.toString(),
        openingNarrationText: j['opening_narration_text'] as String?,
        openingNarrationAudioUrl: j['opening_narration_audio_url'] as String?,
        completionRewardXp: (j['completion_reward_xp'] as num?)?.toInt() ?? 0,
        completionBadge: j['completion_badge'] as String?,
        missionBriefText: j['mission_brief_text'] as String?,
        introCharacterName: j['intro_character_name'] as String?,
        introCharacterId: j['intro_character_id']?.toString(),
        openingVideoUrl: j['opening_video_url'] as String?,
        finalRevealText: j['final_reveal_text'] as String?,
        heroImageUrl: j['hero_image_url'] as String?,
        storyHook: j['story_hook'] as String?,
        imageClueText: j['image_clue_text'] as String?,
        finalRevealVideoUrl: j['final_reveal_video_url'] as String?,
        realHistoryText: j['real_history_text'] as String?,
      );

  Map<String, dynamic> toWrite() => {
        'title': title,
        'description': description,
        'category': category,
        'difficulty': difficulty,
        'estimated_duration_minutes': estimatedDurationMinutes,
        'published': published,
        'starting_location_id': startingLocationId,
        'opening_narration_text': openingNarrationText,
        'opening_narration_audio_url': openingNarrationAudioUrl,
        'completion_reward_xp': completionRewardXp,
        'completion_badge': completionBadge,
        'mission_brief_text': missionBriefText,
        'intro_character_name': introCharacterName,
        'intro_character_id': introCharacterId,
        'opening_video_url': openingVideoUrl,
        'final_reveal_text': finalRevealText,
        'hero_image_url': heroImageUrl,
        'story_hook': storyHook,
        'image_clue_text': imageClueText,
        'final_reveal_video_url': finalRevealVideoUrl,
        'real_history_text': realHistoryText,
      };
}
