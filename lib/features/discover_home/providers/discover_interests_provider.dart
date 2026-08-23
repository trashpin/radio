import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:explorer_os_mobile/features/profile/data/user_profile_repository.dart';

/// The visitor's selected Discover interest tokens. Signed-in users persist
/// to `profiles.interests` (same repository/table every other profile field
/// already uses); guests fall back to local `SharedPreferences` — the same
/// guest-friendly pattern [LocationFavorites] already established for
/// favorites, applied here instead of inventing a second local-storage
/// mechanism. Writes go to both so a guest who later signs in doesn't lose
/// their picks and a signed-in user's picks stay in sync across devices.
class DiscoverInterestsController extends Notifier<Set<String>> {
  static const _prefsKey = 'discover_interests';
  SharedPreferences? _prefs;
  bool _loaded = false;

  @override
  Set<String> build() {
    if (!_loaded) {
      _loaded = true;
      _load();
    }
    return const <String>{};
  }

  Future<void> _load() async {
    final profile = await ref.read(currentUserProfileProvider.future);
    if (profile != null && profile.interests.isNotEmpty) {
      state = profile.interests.toSet();
      return;
    }
    try {
      _prefs = await SharedPreferences.getInstance();
      final saved = _prefs?.getStringList(_prefsKey) ?? const [];
      if (saved.isNotEmpty) state = saved.toSet();
    } catch (_) {
      // No platform prefs (tests) — stay empty rather than fail.
    }
  }

  Future<void> setInterests(Set<String> next) async {
    state = next;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setStringList(_prefsKey, next.toList());
    } catch (_) {}
    // No-ops for guests (see UserProfileRepository.update).
    await ref.read(userProfileRepositoryProvider).update({'interests': next.toList()});
    ref.invalidate(currentUserProfileProvider);
  }

  Future<void> toggle(String token) async {
    final next = {...state};
    if (!next.remove(token)) next.add(token);
    await setInterests(next);
  }
}

final discoverInterestsProvider =
    NotifierProvider<DiscoverInterestsController, Set<String>>(DiscoverInterestsController.new);
