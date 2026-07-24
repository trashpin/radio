import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The persistent shell hosting the bottom navigation bar.
///
/// `StatefulShellRoute` (see `app_router.dart`) supplies a [navigationShell]
/// that tracks the active tab and switches between branches. This widget draws
/// the currently active tab plus the shared `NavigationBar`, so the bar stays
/// put while content changes.
///
/// Tab order (fixed): Home, Explore, Map, Radio, Profile. To change tabs, keep
/// this bar and the branch list in `AppRouter` index-aligned.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goToBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goToBranch,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.radio_outlined),
            selectedIcon: Icon(Icons.radio_rounded),
            label: 'Radio',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
