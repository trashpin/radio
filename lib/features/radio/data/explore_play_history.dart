import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:explorer_os_mobile/features/radio/services/explore_rotation_scheduler.dart';

/// Persists MARION COUNTY EXPLORE's played-content-ID history to disk, so a
/// story already heard doesn't repeat just because the app was closed and
/// reopened (spec: "the recently-played history must survive... closing and
/// reopening the app process").
///
/// [ExploreRotationScheduler] itself stays pure/synchronous (no I/O, so it
/// stays trivially unit-testable) — this is the thin runtime layer that
/// loads history in once at startup and saves it back out after every
/// segment Explore actually plays. Follows the same try/catch-swallow,
/// best-effort SharedPreferences pattern as `StationPreference`/
/// `LocationFavorites` elsewhere in this codebase.
class ExplorePlayHistoryStore {
  static const _key = 'explore_played_content_ids';

  Future<Map<ExploreCategory, Set<String>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final out = <ExploreCategory, Set<String>>{};
      for (final cat in ExploreCategory.values) {
        final ids = decoded[cat.name];
        if (ids is List) out[cat] = ids.map((e) => e.toString()).toSet();
      }
      return out;
    } catch (_) {
      // Non-fatal (e.g. web private mode, corrupt/old data) — start fresh.
      return {};
    }
  }

  Future<void> save(Map<ExploreCategory, Set<String>> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = {
        for (final e in data.entries) e.key.name: e.value.toList(),
      };
      await prefs.setString(_key, jsonEncode(encoded));
    } catch (_) {
      // Best-effort — the in-memory history still works for this session.
    }
  }
}

final explorePlayHistoryStoreProvider =
    Provider<ExplorePlayHistoryStore>((ref) => ExplorePlayHistoryStore());
