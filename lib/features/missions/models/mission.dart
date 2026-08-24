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
    this.finalRevealText,
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
  /// narrator) — shown alongside [openingNarrationText].
  final String? introCharacterName;

  /// "YOU SOLVED IT... you remembered the silver pocket watch..." — the
  /// explanation of how the clues connected, shown at mission completion.
  final String? finalRevealText;

  bool get hasOpeningNarration =>
      (openingNarrationText ?? '').trim().isNotEmpty ||
      (openingNarrationAudioUrl ?? '').trim().isNotEmpty;

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
        finalRevealText: j['final_reveal_text'] as String?,
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
        'final_reveal_text': finalRevealText,
      };
}
