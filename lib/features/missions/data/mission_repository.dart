import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_fact.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_puzzle.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_stop.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_story_step.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_travel_story.dart';
import 'package:explorer_os_mobile/features/missions/models/old_world.dart';
import 'package:explorer_os_mobile/features/missions/models/qr_portal.dart';
import 'package:explorer_os_mobile/features/missions/models/treasure_discovery.dart';

/// Read/write access to the Marion County Adventures content tables
/// (migration 0061). Read-safe: returns `[]`/`null` when Supabase isn't
/// configured or a table doesn't exist yet, matching every other repository
/// in this codebase.
class MissionRepository {
  const MissionRepository();

  Future<List<Mission>> published() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('missions')
          .select()
          .eq('published', true) as List;
      return rows.cast<Map<String, dynamic>>().map(Mission.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Every mission regardless of [Mission.published] — the admin list.
  Future<List<Mission>> all() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('missions')
          .select()
          .order('created_at', ascending: false) as List;
      return rows.cast<Map<String, dynamic>>().map(Mission.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Mission?> byId(String id) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('missions')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : Mission.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  Future<List<MissionStop>> stopsForMission(String missionId) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('mission_stops')
          .select()
          .eq('mission_id', missionId)
          .order('sequence', ascending: true) as List;
      return rows.cast<Map<String, dynamic>>().map(MissionStop.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<MissionTravelStory>> travelStoriesForStop(String stopId) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('mission_travel_stories')
          .select()
          .eq('stop_id', stopId)
          .order('trigger_distance_meters', ascending: false) as List;
      return rows.cast<Map<String, dynamic>>().map(MissionTravelStory.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<OldWorld?> oldWorldById(String id) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('old_worlds')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : OldWorld.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  /// Bulk lookup for "My Discoveries" — every Old World the player has
  /// unlocked across every mission they've played, in one query instead of
  /// one per id.
  Future<List<OldWorld>> oldWorldsByIds(List<String> ids) async {
    if (!SupabaseService.isConfigured || ids.isEmpty) return const [];
    try {
      final rows = await SupabaseService.client
          .from('old_worlds')
          .select()
          .inFilter('id', ids) as List;
      return rows.cast<Map<String, dynamic>>().map(OldWorld.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<QrPortal?> portalById(String id) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('qr_portals')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : QrPortal.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  Future<QrPortal?> portalByCode(String code) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('qr_portals')
          .select()
          .eq('code', code)
          .eq('active', true)
          .maybeSingle();
      return row == null ? null : QrPortal.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  Future<List<MissionFact>> factsForMission(String missionId) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('mission_facts')
          .select()
          .eq('mission_id', missionId) as List;
      return rows.cast<Map<String, dynamic>>().map(MissionFact.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// The mission-level (stop_id null) puzzle — today, always the final
  /// puzzle shown before Mission Complete. Returns the first by [sequence]
  /// if more than one exists.
  Future<MissionPuzzle?> finalPuzzleForMission(String missionId) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final rows = await SupabaseService.client
          .from('mission_puzzles')
          .select()
          .eq('mission_id', missionId)
          .isFilter('stop_id', null)
          .order('sequence', ascending: true)
          .limit(1) as List;
      if (rows.isEmpty) return null;
      return MissionPuzzle.fromJson(rows.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// A stop-level "test of wits" question, shown right after that stop's
  /// QR discovery chapter — distinct from [finalPuzzleForMission], which
  /// gates mission completion. This one never blocks anything (see
  /// [ActiveMissionController.awardBonusXp]): right or wrong, the player
  /// continues either way. Returns the first by [sequence] if more than
  /// one exists.
  Future<MissionPuzzle?> puzzleForStop(String stopId) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final rows = await SupabaseService.client
          .from('mission_puzzles')
          .select()
          .eq('stop_id', stopId)
          .order('sequence', ascending: true)
          .limit(1) as List;
      if (rows.isEmpty) return null;
      return MissionPuzzle.fromJson(rows.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<List<MissionPuzzle>> puzzlesForMission(String missionId) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('mission_puzzles')
          .select()
          .eq('mission_id', missionId)
          .order('sequence', ascending: true) as List;
      return rows.cast<Map<String, dynamic>>().map(MissionPuzzle.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Every character (migration 0065) — a small, global, reusable table, not
  /// scoped to one mission. [ActiveMissionController] loads this once per
  /// mission start and resolves `character_id` -> voice/name from it, rather
  /// than a query per story beat.
  Future<List<MissionCharacter>> allCharacters() async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('mission_characters')
          .select()
          .order('name', ascending: true) as List;
      return rows.cast<Map<String, dynamic>>().map(MissionCharacter.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// A mission's Story Builder sequence, in order. This is the
  /// authoring/production list — it does not affect what the live GPS
  /// player reads (see [MissionStoryStep]'s own doc comment).
  Future<List<MissionStoryStep>> storyStepsForMission(String missionId) async {
    if (!SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('mission_story_steps')
          .select()
          .eq('mission_id', missionId)
          .order('step_order', ascending: true) as List;
      return rows.cast<Map<String, dynamic>>().map(MissionStoryStep.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<String> createStoryStep(Map<String, dynamic> row) async {
    final inserted = await SupabaseService.client
        .from('mission_story_steps')
        .insert(row)
        .select('id')
        .single();
    return inserted['id'].toString();
  }

  Future<void> updateStoryStep(String id, Map<String, dynamic> fields) => _resilient(fields,
      (r) => SupabaseService.client.from('mission_story_steps').update(r).eq('id', id));

  Future<void> deleteStoryStep(String id) =>
      SupabaseService.client.from('mission_story_steps').delete().eq('id', id);

  Future<TreasureDiscovery?> treasureDiscoveryById(String id) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('treasure_discoveries')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : TreasureDiscovery.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  Future<String> createTreasureDiscovery(Map<String, dynamic> row) async {
    final inserted = await SupabaseService.client
        .from('treasure_discoveries')
        .insert(row)
        .select('id')
        .single();
    return inserted['id'].toString();
  }

  Future<void> updateTreasureDiscovery(String id, Map<String, dynamic> fields) => _resilient(
      fields, (r) => SupabaseService.client.from('treasure_discoveries').update(r).eq('id', id));

  Future<MissionCharacter?> characterById(String id) async {
    if (!SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('mission_characters')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : MissionCharacter.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  // ── Admin writes ──────────────────────────────────────────────────────

  Future<String> createMission(Map<String, dynamic> row) async {
    final inserted =
        await SupabaseService.client.from('missions').insert(row).select('id').single();
    return inserted['id'].toString();
  }

  Future<void> updateMission(String id, Map<String, dynamic> fields) =>
      _resilient(fields, (r) => SupabaseService.client.from('missions').update(r).eq('id', id));

  Future<void> deleteMission(String id) =>
      SupabaseService.client.from('missions').delete().eq('id', id);

  Future<String> createStop(Map<String, dynamic> row) async {
    final inserted =
        await SupabaseService.client.from('mission_stops').insert(row).select('id').single();
    return inserted['id'].toString();
  }

  Future<void> updateStop(String id, Map<String, dynamic> fields) => _resilient(
      fields, (r) => SupabaseService.client.from('mission_stops').update(r).eq('id', id));

  Future<void> deleteStop(String id) =>
      SupabaseService.client.from('mission_stops').delete().eq('id', id);

  Future<String> createTravelStory(Map<String, dynamic> row) async {
    final inserted = await SupabaseService.client
        .from('mission_travel_stories')
        .insert(row)
        .select('id')
        .single();
    return inserted['id'].toString();
  }

  Future<void> updateTravelStory(String id, Map<String, dynamic> fields) => _resilient(fields,
      (r) => SupabaseService.client.from('mission_travel_stories').update(r).eq('id', id));

  Future<void> deleteTravelStory(String id) =>
      SupabaseService.client.from('mission_travel_stories').delete().eq('id', id);

  Future<String> createOldWorld(Map<String, dynamic> row) async {
    final inserted =
        await SupabaseService.client.from('old_worlds').insert(row).select('id').single();
    return inserted['id'].toString();
  }

  Future<void> updateOldWorld(String id, Map<String, dynamic> fields) => _resilient(
      fields, (r) => SupabaseService.client.from('old_worlds').update(r).eq('id', id));

  Future<String> createQrPortal(Map<String, dynamic> row) async {
    final inserted =
        await SupabaseService.client.from('qr_portals').insert(row).select('id').single();
    return inserted['id'].toString();
  }

  Future<String> createFact(Map<String, dynamic> row) async {
    final inserted =
        await SupabaseService.client.from('mission_facts').insert(row).select('id').single();
    return inserted['id'].toString();
  }

  Future<void> deleteFact(String id) =>
      SupabaseService.client.from('mission_facts').delete().eq('id', id);

  Future<String> createPuzzle(Map<String, dynamic> row) async {
    final inserted =
        await SupabaseService.client.from('mission_puzzles').insert(row).select('id').single();
    return inserted['id'].toString();
  }

  Future<void> updatePuzzle(String id, Map<String, dynamic> fields) => _resilient(
      fields, (r) => SupabaseService.client.from('mission_puzzles').update(r).eq('id', id));

  Future<void> deletePuzzle(String id) =>
      SupabaseService.client.from('mission_puzzles').delete().eq('id', id);

  Future<String> createCharacter(Map<String, dynamic> row) async {
    final inserted = await SupabaseService.client
        .from('mission_characters')
        .insert(row)
        .select('id')
        .single();
    return inserted['id'].toString();
  }

  Future<void> updateCharacter(String id, Map<String, dynamic> fields) => _resilient(
      fields, (r) => SupabaseService.client.from('mission_characters').update(r).eq('id', id));

  Future<void> deleteCharacter(String id) =>
      SupabaseService.client.from('mission_characters').delete().eq('id', id);

  /// Runs a write, and if it fails only because a column isn't in the schema
  /// cache yet, drops that column and retries (same pattern as every other
  /// repository in this codebase).
  Future<void> _resilient(
    Map<String, dynamic> row,
    Future<void> Function(Map<String, dynamic>) run,
  ) async {
    var current = Map<String, dynamic>.from(row);
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await run(current);
        return;
      } on PostgrestException catch (e) {
        final m = RegExp(r"'([a-zA-Z0-9_]+)' column").firstMatch(e.message);
        final col = m?.group(1);
        if (col == null || !current.containsKey(col)) rethrow;
        current.remove(col);
      }
    }
    await run(current);
  }
}

final missionRepositoryProvider = Provider<MissionRepository>((ref) => const MissionRepository());

class MissionsRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final missionsRefreshProvider = NotifierProvider<MissionsRefresh, int>(MissionsRefresh.new);

/// Published missions — the player-facing adventure list.
final publishedMissionsProvider = FutureProvider<List<Mission>>((ref) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).published();
});

/// Every mission (admin list).
final adminMissionsProvider = FutureProvider<List<Mission>>((ref) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).all();
});

final missionByIdProvider = FutureProvider.family<Mission?, String>((ref, id) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).byId(id);
});

final missionStopsProvider = FutureProvider.family<List<MissionStop>, String>((ref, missionId) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).stopsForMission(missionId);
});

final travelStoriesForStopProvider =
    FutureProvider.family<List<MissionTravelStory>, String>((ref, stopId) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).travelStoriesForStop(stopId);
});

final oldWorldByIdProvider = FutureProvider.family<OldWorld?, String>((ref, id) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).oldWorldById(id);
});

final factsForMissionProvider = FutureProvider.family<List<MissionFact>, String>((ref, missionId) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).factsForMission(missionId);
});

final puzzleForStopProvider = FutureProvider.family<MissionPuzzle?, String>((ref, stopId) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).puzzleForStop(stopId);
});

final finalPuzzleForMissionProvider =
    FutureProvider.family<MissionPuzzle?, String>((ref, missionId) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).finalPuzzleForMission(missionId);
});

final puzzlesForMissionProvider =
    FutureProvider.family<List<MissionPuzzle>, String>((ref, missionId) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).puzzlesForMission(missionId);
});

/// Every character — the admin Character Manager's list, and the source
/// [ActiveMissionController] reads to resolve `character_id` -> voice/name.
final missionCharactersProvider = FutureProvider<List<MissionCharacter>>((ref) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).allCharacters();
});

final missionCharacterByIdProvider = FutureProvider.family<MissionCharacter?, String>((ref, id) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).characterById(id);
});

final treasureDiscoveryByIdProvider = FutureProvider.family<TreasureDiscovery?, String>((ref, id) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).treasureDiscoveryById(id);
});

/// A mission's Story Builder sequence, in order.
final storyStepsForMissionProvider =
    FutureProvider.family<List<MissionStoryStep>, String>((ref, missionId) {
  ref.watch(missionsRefreshProvider);
  return ref.watch(missionRepositoryProvider).storyStepsForMission(missionId);
});
