import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/active_tab_provider.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_shadows.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/core/theme/app_typography.dart';
import 'package:explorer_os_mobile/features/discover_home/presentation/discover_mini_player.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/guide_step_provider.dart';

/// The persistent shell hosting the floating bottom navigation bar.
///
/// `StatefulShellRoute` (see `app_router.dart`) supplies a [navigationShell]
/// that tracks the active tab and switches between branches. This widget draws
/// the active tab plus a shared, floating (rounded, shadowed) `NavigationBar`.
/// `extendBody` lets screen content flow underneath the floating bar for the
/// premium edge-to-edge look.
///
/// ADVENTURE-FIRST: the app's primary purpose is Marion County Adventures —
/// the map, GPS, stories, and everything else are supporting systems for the
/// adventure game, not peers of it. Exactly four primary tabs (fixed
/// order): Adventures (index 0 — the adventure storefront/landing screen),
/// Map (index 1 — the active adventure's game board, or the general explore
/// map when no adventure is active), Guide (index 2 — THE GUIDE's permanent
/// per-adventure companion screen, `GuideHomeScreen`), Discoveries (index 3
/// — the player's journal). To change tabs, keep this bar and the branch
/// list in `AppRouter` index-aligned. Radio, Discover's recommendation feed,
/// Wildlife Guide, and everything else live one tap away via More —
/// reachable from a menu button on each primary screen's app bar, not a
/// fifth bottom tab (see `more_screen.dart`). Radio playback itself stays
/// glanceable/controllable from any primary tab via [DiscoverMiniPlayer],
/// reused as-is (same widget/engine Discover already used it with) rather
/// than earning its own tab.
///
/// The bar is styled as a dark, floating pill with a gold active state (a
/// premium National-Geographic feel) regardless of the app's light/dark mode,
/// so it matches the immersive Radio/Map screens.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const Color _barColor = Color(0xFF141C18);
  static const Color _gold = Color(0xFFF2B33D);
  static const Color _inactive = Color(0xFF8B978F);

  void _goToBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Runs on every branch switch (go_router rebuilds this shell whenever
    // navigationShell.currentIndex changes) — deferred a frame so it never
    // tries to update a provider mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeTabIndexProvider.notifier).value = navigationShell.currentIndex;
    });
    final activeMissionId = ref.watch(activeMissionControllerProvider).mission?.id;
    final hasNewGuideContent = activeMissionId == null
        ? false
        : ref.watch(nextGuideStepProvider(activeMissionId)).value != null;
    final navTheme = NavigationBarThemeData(
      height: 68,
      backgroundColor: _barColor,
      surfaceTintColor: Colors.transparent,
      indicatorColor: _gold.withValues(alpha: 0.18),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected) ? _gold : _inactive,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => AppTypography.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected) ? _gold : _inactive,
        ),
      ),
    );

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Radio stays glanceable/controllable from every primary tab
              // without a tab of its own — see this widget's own doc comment.
              const DiscoverMiniPlayer(),
              const SizedBox(height: AppSpacing.sm),
              DecoratedBox(
                decoration: const BoxDecoration(
                  borderRadius: AppRadius.xlAll,
                  boxShadow: AppShadows.elevated,
                ),
                child: ClipRRect(
                  borderRadius: AppRadius.xlAll,
                  child: NavigationBarTheme(
                    data: navTheme,
                    child: NavigationBar(
                      selectedIndex: navigationShell.currentIndex,
                      onDestinationSelected: _goToBranch,
                      destinations: [
                        const NavigationDestination(
                          icon: Icon(Icons.explore_outlined),
                          selectedIcon: Icon(Icons.explore_rounded),
                          label: 'Adventures',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.map_outlined),
                          selectedIcon: Icon(Icons.map_rounded),
                          label: 'Map',
                        ),
                        NavigationDestination(
                          icon: Badge(
                            isLabelVisible: hasNewGuideContent,
                            backgroundColor: _gold,
                            smallSize: 8,
                            child: const Icon(Icons.person_search_outlined),
                          ),
                          selectedIcon: Badge(
                            isLabelVisible: hasNewGuideContent,
                            backgroundColor: _gold,
                            smallSize: 8,
                            child: const Icon(Icons.person_search_rounded),
                          ),
                          label: 'Guide',
                        ),
                        const NavigationDestination(
                          icon: Icon(Icons.auto_stories_outlined),
                          selectedIcon: Icon(Icons.auto_stories_rounded),
                          label: 'Discoveries',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
