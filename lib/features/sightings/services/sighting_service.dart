import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/sightings/data/sighting_repository.dart';
import 'package:explorer_os_mobile/features/sightings/models/explorer_sighting.dart';
import 'package:explorer_os_mobile/features/sightings/services/ai_ranger_narration_service.dart';

/// Outcome of reporting a sighting.
class SightingResult {
  const SightingResult({
    required this.sighting,
    required this.reaction,
    required this.saved,
    this.error,
  });

  final ExplorerSighting sighting;
  final SightingReaction reaction;

  /// Whether the row was persisted to Supabase.
  final bool saved;

  /// Populated when the save failed (e.g. the table isn't created yet).
  final String? error;
}

/// Orchestrates a sighting report: persist to Supabase, then produce an AI
/// Ranger reaction. If the save fails (e.g. missing table), the reaction is
/// still returned so the UX degrades gracefully.
class SightingService {
  const SightingService(this._repository, this._narration);

  final SightingRepository _repository;
  final AiRangerNarrationService _narration;

  Future<SightingResult> report(ExplorerSighting draft) async {
    try {
      final saved = await _repository.create(draft);
      return SightingResult(
        sighting: saved,
        reaction: _narration.reactTo(saved),
        saved: true,
      );
    } catch (e) {
      return SightingResult(
        sighting: draft,
        reaction: _narration.reactTo(draft),
        saved: false,
        error: e.toString(),
      );
    }
  }
}

final sightingServiceProvider = Provider<SightingService>((ref) {
  return SightingService(
    ref.watch(sightingRepositoryProvider),
    ref.watch(aiRangerNarrationServiceProvider),
  );
});
