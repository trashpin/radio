import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user's chosen radio station genre (Country / Rock / Top Hits / Kids),
/// persisted locally so the app reopens on their preferred station.
class StationPreference extends Notifier<String?> {
  static const String prefsKey = 'radio_station_genre';

  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getString(prefsKey);
    } catch (_) {
      // Non-fatal (e.g. web private mode) — leave unset.
    }
  }

  Future<void> select(String genre) async {
    state = genre;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, genre);
    } catch (_) {
      // Keep the in-memory choice even if persistence fails.
    }
  }
}

final stationPreferenceProvider =
    NotifierProvider<StationPreference, String?>(StationPreference.new);
