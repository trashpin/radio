import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/sightings/models/explorer_sighting.dart';

/// A canned AI Ranger reaction to a sighting.
class SightingReaction {
  const SightingReaction(this.text);
  final String text;
}

/// Placeholder AI Ranger narration.
///
/// FUTURE SEAM: this is where OpenAI (identification/text) and ElevenLabs (TTS)
/// will plug in. Today it returns a friendly, deterministic reaction with NO
/// external calls — keeping the app buildable/testable and cost-free.
class AiRangerNarrationService {
  const AiRangerNarrationService();

  SightingReaction reactTo(ExplorerSighting sighting) {
    final species = (sighting.species?.trim().isNotEmpty ?? false)
        ? sighting.species!.trim()
        : sighting.category.label.toLowerCase();
    final where =
        (sighting.parkName?.isNotEmpty ?? false) ? sighting.parkName! : 'this area';
    return SightingReaction(
      'Great find! That appears to be a $species. These are commonly seen in '
      '$where — thanks for logging it.',
    );
  }
}

final aiRangerNarrationServiceProvider =
    Provider<AiRangerNarrationService>((ref) => const AiRangerNarrationService());
