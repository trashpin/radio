/// The ElevenLabs voices configured in ExplorerOS, used by the narration voice
/// dropdowns and the audio generator. `id` is the ElevenLabs voice id.
class NarrationVoiceOption {
  const NarrationVoiceOption(this.id, this.name);
  final String id;
  final String name;
}

const narrationVoices = <NarrationVoiceOption>[
  NarrationVoiceOption('pNInz6obpgDQGcFmaJgB', 'National Park Ranger (Adam)'),
  NarrationVoiceOption('ErXwobaYiN019PkySvjV', 'Friendly Tour Guide (Antoni)'),
  NarrationVoiceOption('TxGEqnHWrfWFTfGW9XjX', 'Campfire Storyteller (Josh)'),
  NarrationVoiceOption('MF3mGyEYCl7XYWbV9V6O', 'Kids Adventure Guide (Elli)'),
  NarrationVoiceOption('VR6AewLTigWG4xSOukaG', 'Southern Storyteller (Arnold)'),
  NarrationVoiceOption('kPzsL2i3teMYv0FxEYQ6', 'DJ Brittney'),
  NarrationVoiceOption('21m00Tcm4TlvDq8ikWAM', 'Rachel'),
  NarrationVoiceOption('EXAVITQu4vr4xnSDxMaL', 'Bella'),
  NarrationVoiceOption('AZnzlk1XvdvUeBnXmlld', 'Domi'),
];

/// Fallback voice when nothing is selected anywhere (last resort).
const kFallbackVoiceId = 'pNInz6obpgDQGcFmaJgB';
const kFallbackVoiceName = 'National Park Ranger (Adam)';

String? voiceNameForId(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final v in narrationVoices) {
    if (v.id == id) return v.name;
  }
  return null;
}
