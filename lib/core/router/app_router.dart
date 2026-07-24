import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/destinations/destinations_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/map/map_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/radio/radio_screen.dart';
import '../../features/settings/settings_screen.dart';
import 'app_scaffold.dart';

/// Strongly-typed list of app routes.
///
/// Using an enum instead of scattering raw path strings ("/home", "/map", ...)
/// throughout the code prevents typos and makes navigation refactors safe.
enum AppRoute {
  home('/home'),
  destinations('/destinations'),
  map('/map'),
  radio('/radio'),
  profile('/profile'),
  settings('/settings');

  const AppRoute(this.path);
  final String path;
}

/// Central navigation configuration for ExplorerOS-Mobile.
///
/// We use `go_router` with a [StatefulShellRoute] — the modern Flutter pattern
/// for bottom-navigation apps. Each tab is a "branch" that keeps its own
/// navigation stack and scroll position when you switch tabs. The visual shell
/// (the `NavigationBar`) lives in `AppScaffold`; this file wires the branches
/// to that shell.
///
/// Settings is declared OUTSIDE the shell so it opens as a full-screen pushed
/// route (no bottom bar), reflecting that it is a detail screen, not a tab.
class AppRouter {
  const AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoute.home.path,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          // AppScaffold renders the bottom NavigationBar and the active branch.
          return AppScaffold(navigationShell: navigationShell);
        },
        branches: [
          _branch(AppRoute.home.path, const HomeScreen()),
          _branch(AppRoute.destinations.path, const DestinationsScreen()),
          _branch(AppRoute.map.path, const MapScreen()),
          _branch(AppRoute.radio.path, const RadioScreen()),
          _branch(AppRoute.profile.path, const ProfileScreen()),
        ],
      ),
      GoRoute(
        path: AppRoute.settings.path,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );

  /// Helper that wraps a screen in a single-route navigation branch, reducing
  /// boilerplate in the branch list above.
  static StatefulShellBranch _branch(String path, Widget child) {
    return StatefulShellBranch(
      routes: [GoRoute(path: path, builder: (context, state) => child)],
    );
  }
}
