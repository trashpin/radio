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
  });

  final String id;
  final String title;
  final String? description;

  /// Free text, e.g. 'history', 'mystery', 'nature', 'wildlife', 'springs',
  /// 'treasure' — matches this app's existing free-text category convention
  /// (never a fixed enum) so new mission themes never need a migration.
  final String? category;

  /// 'easy' | 'moderate' | 'hard'.
  final String? difficulty;
  final int? estimatedDurationMinutes;
  final bool published;
  final String? startingLocationId;
  final String? openingNarrationText;
  final String? openingNarrationAudioUrl;
  final int completionRewardXp;
  final String? completionBadge;

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
      };
}
