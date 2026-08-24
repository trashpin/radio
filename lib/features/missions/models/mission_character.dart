/// A reusable Marion County Adventures character (`mission_characters`,
/// migration 0065). CHARACTER -> VOICE ID: [voiceId] is the ElevenLabs voice
/// this character always speaks with — every story scene that names this
/// character automatically uses it, so a voice is never re-picked per scene
/// (see [ActiveMissionController]'s character resolution).
class MissionCharacter {
  const MissionCharacter({
    required this.id,
    required this.name,
    this.imageUrl,
    this.description,
    this.characterType,
    this.personality,
    this.role,
    this.voiceId,
    this.heygenAvatarId,
    this.heygenAvatarType = kHeygenAvatarTypeTalkingPhoto,
    this.active = true,
  });

  final String id;
  final String name;
  final String? imageUrl;
  final String? description;

  /// Free text, not a fixed enum — suggested vocabulary: narrator,
  /// historical_character, fictional_character, explorer, historian,
  /// ranger, local_guide, mystery_character.
  final String? characterType;

  /// E.g. "Curious, determined, mysterious" — shown in the admin editor and
  /// available for the adventure introduction, never spoken verbatim.
  final String? personality;
  final String? role;
  final String? voiceId;

  /// The HeyGen avatar this character always appears as in AVATAR VIDEO
  /// presentation steps — the same "assign once, inherit everywhere" rule
  /// as [voiceId]. No HeyGen integration exists in this app yet (see
  /// `HeyGenAvatarService`'s own doc comment) — this field exists so it can
  /// be wired in later without another migration.
  final String? heygenAvatarId;

  /// Which HeyGen character shape [heygenAvatarId] is: [kHeygenAvatarTypeAvatar]
  /// for a stock/studio avatar_id, [kHeygenAvatarTypeTalkingPhoto] for a
  /// custom photo avatar (talking_photo_id) an admin trained in HeyGen
  /// directly. These use different request shapes in the HeyGen API — not
  /// interchangeable, so getting this wrong means the video generates from
  /// the wrong (or a default) character.
  final String heygenAvatarType;
  final bool active;

  bool get hasVoice => (voiceId ?? '').trim().isNotEmpty;
  bool get hasAvatar => (heygenAvatarId ?? '').trim().isNotEmpty;

  factory MissionCharacter.fromJson(Map<String, dynamic> j) => MissionCharacter(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '') as String,
        imageUrl: j['image_url'] as String?,
        description: j['description'] as String?,
        characterType: j['character_type'] as String?,
        personality: j['personality'] as String?,
        role: j['role'] as String?,
        voiceId: j['voice_id'] as String?,
        heygenAvatarId: j['heygen_avatar_id'] as String?,
        heygenAvatarType:
            (j['heygen_avatar_type'] ?? kHeygenAvatarTypeTalkingPhoto) as String,
        active: (j['active'] ?? true) as bool,
      );

  Map<String, dynamic> toWrite() => {
        'name': name,
        'image_url': imageUrl,
        'description': description,
        'character_type': characterType,
        'personality': personality,
        'role': role,
        'voice_id': voiceId,
        'heygen_avatar_id': heygenAvatarId,
        'heygen_avatar_type': heygenAvatarType,
        'active': active,
      };
}

const kHeygenAvatarTypeAvatar = 'avatar';
const kHeygenAvatarTypeTalkingPhoto = 'talking_photo';
const List<String> kHeygenAvatarTypes = [kHeygenAvatarTypeTalkingPhoto, kHeygenAvatarTypeAvatar];

/// Suggested character types (free text — not enforced) shown in the admin
/// editor's dropdown.
const List<String> kMissionCharacterTypes = [
  'narrator',
  'historical_character',
  'fictional_character',
  'explorer',
  'historian',
  'ranger',
  'local_guide',
  'mystery_character',
];
