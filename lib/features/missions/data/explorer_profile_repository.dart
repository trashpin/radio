import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/missions/models/explorer_profile.dart';

String? _currentUserId() {
  if (!SupabaseService.isConfigured) return null;
  return SupabaseService.client.auth.currentUser?.id;
}

/// Reads/writes the signed-in player's `explorer_profiles` row (migration
/// 0074, self-only RLS) — whether they've met THE GUIDE yet and become an
/// Explorer. No-op for guests: [current] returns an in-memory
/// `not_started` profile rather than erroring, matching
/// [MissionProgressRepository]'s guest-mode convention, so a signed-out
/// session can still see (and replay) the Guide intro without persisting
/// anything.
class ExplorerProfileRepository {
  const ExplorerProfileRepository();

  Future<ExplorerProfile> current() async {
    final uid = _currentUserId();
    if (uid == null || !SupabaseService.isConfigured) {
      return const ExplorerProfile(id: '', userId: '');
    }
    try {
      final row = await SupabaseService.client
          .from('explorer_profiles')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (row != null) return ExplorerProfile.fromJson(row);
      final inserted = await SupabaseService.client
          .from('explorer_profiles')
          .insert({'user_id': uid, 'guide_status': kGuideStatusNotStarted})
          .select()
          .single();
      return ExplorerProfile.fromJson(inserted);
    } catch (_) {
      return ExplorerProfile(id: '', userId: uid);
    }
  }

  Future<void> _setStatus(String status, {bool setActivatedAt = false}) async {
    final uid = _currentUserId();
    if (uid == null || !SupabaseService.isConfigured) return;
    try {
      await SupabaseService.client.from('explorer_profiles').update({
        'guide_status': status,
        if (setActivatedAt) 'activated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('user_id', uid);
    } catch (_) {}
  }

  Future<void> markIntroductionStarted() => _setStatus(kGuideStatusIntroductionStarted);
  Future<void> markIntroductionCompleted() => _setStatus(kGuideStatusIntroductionCompleted);
  Future<void> activateExplorer() =>
      _setStatus(kGuideStatusExplorerActivated, setActivatedAt: true);
}

final explorerProfileRepositoryProvider =
    Provider<ExplorerProfileRepository>((ref) => const ExplorerProfileRepository());

class ExplorerProfileRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final explorerProfileRefreshProvider =
    NotifierProvider<ExplorerProfileRefresh, int>(ExplorerProfileRefresh.new);

final explorerProfileProvider = FutureProvider<ExplorerProfile>((ref) {
  ref.watch(explorerProfileRefreshProvider);
  return ref.watch(explorerProfileRepositoryProvider).current();
});
