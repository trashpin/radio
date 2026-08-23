import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The currently active primary-nav branch index (see `AppShell`/`AppRouter`
/// — Discover=0, Map=1, Wildlife Guide=2, More=3). Kept up to date by
/// `AppShell` on every build. Exists so a tab that stays mounted the whole
/// time (Flutter's `StatefulShellRoute.indexedStack` never disposes an
/// inactive branch) can still tell "the user switched away and came back"
/// apart from an ordinary rebuild while already active — e.g. Discover's
/// opening greeting should only play again on a genuine return visit, never
/// just because the visitor scrolled.
class ActiveTabIndex extends Notifier<int> {
  @override
  int build() => 0;

  set value(int v) {
    if (state != v) state = v;
  }
}

final activeTabIndexProvider = NotifierProvider<ActiveTabIndex, int>(ActiveTabIndex.new);
