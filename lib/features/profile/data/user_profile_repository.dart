import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/profile/models/user_profile.dart';

/// Reads/writes the signed-in user's `public.profiles` row.
class UserProfileRepository {
  const UserProfileRepository();

  Future<UserProfile?> current() async {
    if (!SupabaseService.isConfigured) return null;
    final uid = _currentUserId();
    if (uid == null) return null;
    try {
      final row = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      return row == null ? null : UserProfile.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  /// Upserts fields on the current user's profile (e.g. names after sign-up,
  /// preferences, favorites). No-op for guests.
  Future<void> update(Map<String, dynamic> fields) async {
    if (!SupabaseService.isConfigured) return;
    final uid = _currentUserId();
    if (uid == null) return;
    try {
      await SupabaseService.client.from('profiles').upsert({
        'id': uid,
        ...fields,
      });
    } catch (_) {}
  }
}

String? _currentUserId() {
  if (!SupabaseService.isConfigured) return null;
  return SupabaseService.client.auth.currentUser?.id;
}

final userProfileRepositoryProvider =
    Provider<UserProfileRepository>((ref) => const UserProfileRepository());

/// The current user's profile (null for guests / signed-out). Invalidate after
/// sign-in/out to refresh.
final currentUserProfileProvider = FutureProvider<UserProfile?>((ref) {
  return ref.watch(userProfileRepositoryProvider).current();
});
