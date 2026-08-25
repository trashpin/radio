import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_progress.dart';

String? _currentUserId() {
  if (!SupabaseService.isConfigured) return null;
  return SupabaseService.client.auth.currentUser?.id;
}

/// Reads/writes the signed-in player's `mission_progress` rows (migration
/// 0061, self-only RLS). No-op for guests — the mission player screen falls
/// back to in-memory-only progress for a signed-out session rather than
/// erroring (matches this app's "guest mode" convention elsewhere).
class MissionProgressRepository {
  const MissionProgressRepository();

  Future<MissionProgress?> forMission(String missionId) async {
    final uid = _currentUserId();
    if (uid == null || !SupabaseService.isConfigured) return null;
    try {
      final row = await SupabaseService.client
          .from('mission_progress')
          .select()
          .eq('user_id', uid)
          .eq('mission_id', missionId)
          .maybeSingle();
      return row == null ? null : MissionProgress.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  /// Every in-progress/completed mission for the "My Journey" list.
  Future<List<MissionProgress>> all() async {
    final uid = _currentUserId();
    if (uid == null || !SupabaseService.isConfigured) return const [];
    try {
      final rows = await SupabaseService.client
          .from('mission_progress')
          .select()
          .eq('user_id', uid) as List;
      return rows.cast<Map<String, dynamic>>().map(MissionProgress.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Creates a fresh in-progress row when a player starts a mission for the
  /// first time; returns the existing row unchanged if one already exists
  /// (resuming, not restarting).
  Future<MissionProgress?> startOrResume(String missionId, String firstStopId) async {
    final uid = _currentUserId();
    if (uid == null || !SupabaseService.isConfigured) return null;
    final existing = await forMission(missionId);
    if (existing != null) return existing;
    try {
      final row = await SupabaseService.client.from('mission_progress').insert({
        'user_id': uid,
        'mission_id': missionId,
        'current_stop_id': firstStopId,
        'status': 'in_progress',
        'started_at': DateTime.now().toUtc().toIso8601String(),
      }).select().single();
      return MissionProgress.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(MissionProgress progress) async {
    if (!SupabaseService.isConfigured) return;
    try {
      await SupabaseService.client
          .from('mission_progress')
          .update(progress.toWrite())
          .eq('id', progress.id);
    } catch (_) {}
  }
}

final missionProgressRepositoryProvider =
    Provider<MissionProgressRepository>((ref) => const MissionProgressRepository());

/// Bumped whenever [ActiveMissionController] persists progress (stop
/// completed, mission completed) — lets "My Discoveries" and the Adventure
/// Card's progress badge know to refetch instead of showing stale data for
/// the rest of the app session.
class MissionProgressRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final missionProgressRefreshProvider =
    NotifierProvider<MissionProgressRefresh, int>(MissionProgressRefresh.new);

/// One mission's progress for the signed-in player — powers the Adventure
/// Card's "In Progress"/"Completed" badge.
final missionProgressProvider =
    FutureProvider.family<MissionProgress?, String>((ref, missionId) {
  ref.watch(missionProgressRefreshProvider);
  return ref.watch(missionProgressRepositoryProvider).forMission(missionId);
});

/// Every mission the signed-in player has started or finished — the raw
/// data source for "My Discoveries".
final allMissionProgressProvider = FutureProvider<List<MissionProgress>>((ref) {
  ref.watch(missionProgressRefreshProvider);
  return ref.watch(missionProgressRepositoryProvider).all();
});
