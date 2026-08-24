import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_stop.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_travel_story.dart';
import 'package:explorer_os_mobile/features/missions/models/old_world.dart';
import 'package:explorer_os_mobile/features/missions/models/qr_portal.dart';

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
