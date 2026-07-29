import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locally-persisted favorite master-location ids (works for guests too).
/// Backs the "Save Favorite" action on the universal Destination Detail card.
class LocationFavorites extends Notifier<Set<String>> {
  static const _key = 'favorite_location_ids';
  SharedPreferences? _prefs;

  @override
  Set<String> build() {
    _load();
    return <String>{};
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final ids = _prefs?.getStringList(_key) ?? const [];
      state = ids.toSet();
    } catch (_) {
      // No platform prefs (tests) → stay in-memory.
    }
  }

  bool contains(String id) => state.contains(id);

  Future<void> toggle(String id) async {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    state = next;
    try {
      await _prefs?.setStringList(_key, next.toList());
    } catch (_) {}
  }
}

final locationFavoritesProvider =
    NotifierProvider<LocationFavorites, Set<String>>(LocationFavorites.new);
