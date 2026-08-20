import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/ambient_sounds/models/ambient_sound.dart';

/// Reads the `ambient_sounds` library. Defensive: returns [] when the table
/// doesn't exist yet or Supabase is unavailable — the ambient layer is always
/// optional, never something Explore can be silent without.
class AmbientSoundsRepository {
  const AmbientSoundsRepository();

  Future<List<AmbientSound>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows =
          await SupabaseService.client.from('ambient_sounds').select() as List;
      return rows
          .cast<Map<String, dynamic>>()
          .map(AmbientSound.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

final ambientSoundsRepositoryProvider = Provider<AmbientSoundsRepository>(
    (ref) => const AmbientSoundsRepository());

final ambientSoundsProvider = FutureProvider<List<AmbientSound>>((ref) {
  return ref.watch(ambientSoundsRepositoryProvider).all();
});

/// Active, playable sounds grouped by [AmbientSound.type] — the lookup
/// Explore's candidate builder uses to resolve a content record's
/// `ambient_type` into an actual playable URL (varying between several clips
/// of the same type when more than one exists).
final activeAmbientSoundsByTypeProvider =
    Provider<Map<String, List<AmbientSound>>>((ref) {
  final all = ref.watch(ambientSoundsProvider).value ?? const <AmbientSound>[];
  final out = <String, List<AmbientSound>>{};
  for (final s in all) {
    if (!s.active || (s.audioUrl ?? '').trim().isEmpty) continue;
    (out[s.type] ??= []).add(s);
  }
  return out;
});
