import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The persistent shell that hosts the bottom navigation bar.
///
/// `StatefulShellRoute` (see `app_router.dart`) hands us a [navigationShell]
/// object that knows which tab (branch) is active and how to switch between
/// them. This widget renders the currently active tab's screen plus the shared
/// `NavigationBar`, so the bar stays put while the content above it changes.
///
/// Bottom navigation order is fixed here: Home, Destinations, Map, Radio,
/// Profile. To add/reorder tabs, update both this bar and the branch list in
/// `AppRouter` so their indexes stay in sync.
class AppScaffold extends StatelessWidget {
  const AppScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Switches tabs. Passing `initialLocation: true` when re-tapping the current
  /// tab pops it back to its root — standard bottom-nav behavior.
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
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Destinations',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.radio_outlined),
            selectedIcon: Icon(Icons.radio),
            label: 'Radio',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
