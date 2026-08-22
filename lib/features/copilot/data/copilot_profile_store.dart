import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:explorer_os_mobile/features/copilot/models/copilot_profile.dart';

/// Locally-persisted Copilot profile — same hand-rolled SharedPreferences
/// shape as `LocationFavorites`/`StationPreference` (no generic prefs helper
/// exists in this repo to reuse). Entirely on-device; nothing here is ever
/// sent anywhere except as short text hints in a `copilot-line` request.
///
/// `reset()` gives the settings UI a one-call "forget everything" action —
/// spec §7: "the user should be able to view, change, or reset their
/// preferences."
class CopilotProfileStore extends Notifier<CopilotProfile> {
  static const _key = 'copilot_profile_v1';
  SharedPreferences? _prefs;

  @override
  CopilotProfile build() {
    _load();
    return CopilotProfile.empty;
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs?.getString(_key);
      if (raw == null || raw.isEmpty) return;
      state = CopilotProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // No platform prefs (tests) or corrupt data → stay at the default.
    }
  }

  Future<void> _save() async {
    try {
      await _prefs?.setString(_key, jsonEncode(state.toJson()));
    } catch (_) {}
  }

  Future<void> update(CopilotProfile Function(CopilotProfile) transform) async {
    state = transform(state);
    await _save();
  }

  Future<void> reset() async {
    state = CopilotProfile.empty;
    try {
      await _prefs?.remove(_key);
    } catch (_) {}
  }
}

final copilotProfileProvider =
    NotifierProvider<CopilotProfileStore, CopilotProfile>(CopilotProfileStore.new);
