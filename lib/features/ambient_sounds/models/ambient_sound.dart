/// A single reusable, admin-authored ambient-sound clip (flowing water,
/// birds, swamp, forest, ...) — mirrors the `ambient_sounds` table. Several
/// clips may share the same [type] so playback can vary which one is used.
class AmbientSound {
  const AmbientSound({
    required this.id,
    required this.name,
    required this.type,
    this.audioUrl,
    this.active = true,
    this.description,
  });

  final String id;
  final String name;
  final String type;
  final String? audioUrl;
  final bool active;
  final String? description;

  factory AmbientSound.fromJson(Map<String, dynamic> j) => AmbientSound(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '') as String,
        type: (j['type'] ?? '') as String,
        audioUrl: j['audio_url'] as String?,
        active: (j['active'] as bool?) ?? true,
        description: j['description'] as String?,
      );
}

/// Known ambient-sound types — shared by the Ambient Sounds admin page's own
/// `type` field and Location Content's `ambient_type` picker, so both only
/// ever offer a type an actual clip can exist for. `none` is not listed here;
/// it's represented by leaving `ambient_type` unset (spec: "Do NOT force an
/// ambient effect onto every story").
const List<String> kAmbientSoundTypes = [
  'flowing_water',
  'spring_water',
  'birds',
  'swamp',
  'frogs',
  'forest',
  'wind',
  'rain',
  'horses',
  'insects',
  'river',
  'lake',
];
