/// An ElevenLabs voice available for narration generation.
class Voice {
  const Voice({
    required this.voiceId,
    required this.name,
    this.description,
    this.gender,
    this.style,
    this.suggestedCategory,
    this.previewUrl,
    this.language = 'English',
    this.active = true,
  });

  final String voiceId;
  final String name;
  final String? description;
  final String? gender;
  final String? style;

  /// Category this voice is a good default for (e.g. 'birds').
  final String? suggestedCategory;

  /// Public sample clip URL (plays without the API key).
  final String? previewUrl;
  final String language;
  final bool active;

  factory Voice.fromJson(Map<String, dynamic> j) => Voice(
        voiceId: (j['voice_id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        description: j['description'] as String?,
        gender: j['gender'] as String?,
        style: j['style'] as String?,
        suggestedCategory: j['suggested_category'] as String?,
        previewUrl: j['preview_url'] as String?,
        language: (j['language'] ?? 'English') as String,
        active: (j['active'] ?? true) as bool,
      );
}
