import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/missions/models/game_guide_step.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';

/// Read/write access to THE GUIDE's permanent content (`game_guide_steps`,
/// migration 0074) and identity (a `mission_characters` row with
/// `character_type = 'local_guide'` — reused as-is, not duplicated here).
/// Read-safe: returns `[]`/`null` when Supabase isn't configured, matching
/// every other repository in this app.
class GameGuideRepository {
  const GameGuideRepository();

  /// The active Guide's character record — name/image/personality/voice/
  /// avatar all live here, edited in the existing Character Manager.
  Future<MissionCharacter?> activeGuideCharacter() async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('mission_characters')
          .select()
          .eq('character_type', 'local_guide')
          .eq('active', true)
          .limit(1)
          .maybeSingle();
      return row == null ? null : MissionCharacter.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  /// All Guide content steps, active-only, in play order — what
  /// [GuideIntroScreen] plays through.
  Future<List<GameGuideStep>> activeSteps() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('game_guide_steps')
          .select()
          .eq('active', true)
          .order('step_order', ascending: true) as List;
      return rows.cast<Map<String, dynamic>>().map(GameGuideStep.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Every step, active or not — the admin editor's full list.
  Future<List<GameGuideStep>> allSteps() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('game_guide_steps')
          .select()
          .order('step_order', ascending: true) as List;
      return rows.cast<Map<String, dynamic>>().map(GameGuideStep.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String> createStep(Map<String, dynamic> row) async {
    final inserted = await SupabaseService.client
        .from('game_guide_steps')
        .insert(row)
        .select('id')
        .single();
    return inserted['id'].toString();
  }

  Future<void> updateStep(String id, Map<String, dynamic> fields) =>
      SupabaseService.client.from('game_guide_steps').update(fields).eq('id', id);

  Future<void> deleteStep(String id) =>
      SupabaseService.client.from('game_guide_steps').delete().eq('id', id);
}

final gameGuideRepositoryProvider =
    Provider<GameGuideRepository>((ref) => const GameGuideRepository());

class GameGuideRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final gameGuideRefreshProvider = NotifierProvider<GameGuideRefresh, int>(GameGuideRefresh.new);

final activeGuideCharacterProvider = FutureProvider<MissionCharacter?>((ref) {
  ref.watch(gameGuideRefreshProvider);
  return ref.watch(gameGuideRepositoryProvider).activeGuideCharacter();
});

final activeGuideStepsProvider = FutureProvider<List<GameGuideStep>>((ref) {
  ref.watch(gameGuideRefreshProvider);
  return ref.watch(gameGuideRepositoryProvider).activeSteps();
});

final allGuideStepsProvider = FutureProvider<List<GameGuideStep>>((ref) {
  ref.watch(gameGuideRefreshProvider);
  return ref.watch(gameGuideRepositoryProvider).allSteps();
});
