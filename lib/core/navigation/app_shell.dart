import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_shadows.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/core/theme/app_typography.dart';

/// The persistent shell hosting the floating bottom navigation bar.
///
/// `StatefulShellRoute` (see `app_router.dart`) supplies a [navigationShell]
/// that tracks the active tab and switches between branches. This widget draws
/// the active tab plus a shared, floating (rounded, shadowed) `NavigationBar`.
/// `extendBody` lets screen content flow underneath the floating bar for the
/// premium edge-to-edge look.
///
/// Tab order (fixed): Radio, Map, Wildlife Guide, More. To change tabs, keep
/// this bar and the branch list in `AppRouter` index-aligned. Explore and
/// Stories were removed from the primary nav (still reachable from the More
/// tab) — see `more_screen.dart`.
///
/// The bar is styled as a dark, floating pill with a gold active state (a
/// premium National-Geographic feel) regardless of the app's light/dark mode,
/// so it matches the immersive Radio/Map screens.
class AppShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
          child: DecoratedBox(
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
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.podcasts_outlined),
                      selectedIcon: Icon(Icons.podcasts_rounded),
                      label: 'Radio',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.map_outlined),
                      selectedIcon: Icon(Icons.map_rounded),
                      label: 'Map',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.pets_outlined),
                      selectedIcon: Icon(Icons.pets_rounded),
                      label: 'Wildlife Guide',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.more_horiz_rounded),
                      selectedIcon: Icon(Icons.more_horiz_rounded),
                      label: 'More',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
