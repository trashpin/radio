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
    this.revealsFactKeys = const [],
  });

  final String id;
  final String title;
  final String? historicalPeriod;
  final String? voiceId;

  /// Named [MissionFact.key]s this Old World reveals when its narration
  /// plays — same mechanism as [MissionTravelStory.revealsFactKeys].
  final List<String> revealsFactKeys;

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
        'reveals_fact_keys': revealsFactKeys,
      };
}
