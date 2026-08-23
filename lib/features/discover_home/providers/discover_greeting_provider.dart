import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discover_greeting_context.dart';
import 'package:explorer_os_mobile/features/discover_home/providers/discover_interests_provider.dart';
import 'package:explorer_os_mobile/features/discover_home/providers/discover_items_provider.dart';
import 'package:explorer_os_mobile/features/discover_home/services/discover_greeting_selector.dart';
import 'package:explorer_os_mobile/features/profile/data/user_profile_repository.dart';
import 'package:explorer_os_mobile/features/weather/current_weather.dart';
import 'package:explorer_os_mobile/features/weather/weather_service.dart';

/// A coarse "what has this visitor mostly been doing lately" read of
/// `discover_interactions` (migration 0053's write-only seam) — the smallest
/// useful first increment of the "eventually the system can consider recent
/// activity" spec ask, not a new behavioral system. Best-effort: any
/// failure (offline, guest, no history yet) just yields
/// [BehaviorFlavor.none], never an error.
final discoverRecentBehaviorFlavorProvider =
    FutureProvider<BehaviorFlavor>((ref) async {
  if (!SupabaseService.isConfigured) return BehaviorFlavor.none;
  final uid = SupabaseService.client.auth.currentUser?.id;
  if (uid == null) return BehaviorFlavor.none;
  try {
    final rows = await SupabaseService.client
        .from('discover_interactions')
        .select('item_type')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(5)
        .timeout(const Duration(seconds: 4));
    final types = (rows as List)
        .map((r) => (r as Map)['item_type'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
    if (types.isEmpty) return BehaviorFlavor.none;
    final tally = <String, int>{};
    for (final t in types) {
      tally[t] = (tally[t] ?? 0) + 1;
    }
    final top = tally.entries.reduce((a, b) => a.value >= b.value ? a : b);
    // Require a real pattern (2+ of the last 5), not one stray tap.
    if (top.value < 2) return BehaviorFlavor.none;
    return switch (top.key) {
      'gem' => BehaviorFlavor.gem,
      'location' => BehaviorFlavor.location,
      'event' => BehaviorFlavor.event,
      _ => BehaviorFlavor.none,
    };
  } catch (_) {
    return BehaviorFlavor.none;
  }
});

class DiscoverGreetingState {
  const DiscoverGreetingState({required this.id, required this.text});
  final String id;
  final String text;
}

/// Picks and remembers the Discover opening line for this app session.
/// Computed once (not on every rebuild) so the greeting doesn't change under
/// the visitor while they're looking at it; call [reroll] for a fresh pick.
class DiscoverGreetingController extends AsyncNotifier<DiscoverGreetingState> {
  static const _historyKey = 'discover_greeting_history';
  static const _lastOpenKey = 'discover_last_open_at';
  static const _historyLimit = 8;
  static const _selector = DiscoverGreetingSelector();

  @override
  Future<DiscoverGreetingState> build() async {
    String? name;
    try {
      final profile = await ref.watch(currentUserProfileProvider.future);
      name = profile?.firstName;
    } catch (_) {
      // Guest / not signed in — greet without a name.
    }

    final interests = ref.watch(discoverInterestsProvider);
    final weather = ref.watch(currentWeatherProvider);
    final hasRealLocation = ref.watch(discoverHasRealLocationProvider);
    final behaviorFlavor =
        await ref.watch(discoverRecentBehaviorFlavorProvider.future);

    List<String> history = const [];
    int? daysSinceLastOpen;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      history = prefs.getStringList(_historyKey) ?? const [];
      final lastOpenMs = prefs.getInt(_lastOpenKey);
      if (lastOpenMs != null) {
        daysSinceLastOpen = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(lastOpenMs))
            .inDays;
      }
      await prefs.setInt(_lastOpenKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // No platform prefs (tests) — proceed without history/recency.
    }

    final now = DateTime.now();
    final context = DiscoverGreetingContext(
      name: name,
      hour: now.hour,
      weekday: now.weekday,
      interests: interests,
      weatherFlavor: _weatherFlavor(weather),
      behaviorFlavor: behaviorFlavor,
      hasRealLocation: hasRealLocation,
      daysSinceLastOpen: daysSinceLastOpen,
    );

    final template = _selector.select(context: context, recentlyUsed: history);

    final nextHistory = [...history, template.id];
    if (nextHistory.length > _historyLimit) {
      nextHistory.removeRange(0, nextHistory.length - _historyLimit);
    }
    try {
      await prefs?.setStringList(_historyKey, nextHistory);
    } catch (_) {}

    return DiscoverGreetingState(id: template.id, text: template.render(name));
  }

  WeatherFlavor _weatherFlavor(WeatherData? w) {
    if (w == null) return WeatherFlavor.none;
    final cond = w.condition.toLowerCase();
    final rainy = (w.rainChance ?? 0) >= 50 ||
        cond.contains('rain') ||
        cond.contains('storm') ||
        cond.contains('shower');
    if (rainy) return WeatherFlavor.rain;
    final pleasant = cond.contains('clear') ||
        cond.contains('sunny') ||
        cond.contains('partly');
    final temp = w.temperatureF ?? w.highF;
    if (pleasant && temp != null && temp >= 55 && temp <= 92) {
      return WeatherFlavor.good;
    }
    return WeatherFlavor.none;
  }

  /// Picks a fresh line without waiting for a new app session — e.g. a
  /// "shuffle" tap on the greeting header.
  Future<void> reroll() async {
    ref.invalidateSelf();
    await future;
  }
}

final discoverGreetingProvider =
    AsyncNotifierProvider<DiscoverGreetingController, DiscoverGreetingState>(
  DiscoverGreetingController.new,
);
