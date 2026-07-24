import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/navigation/app_shell.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/destination_details_screen.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/destinations_screen.dart';
import 'package:explorer_os_mobile/features/downloads/presentation/downloads_screen.dart';
import 'package:explorer_os_mobile/features/gps/presentation/gps_screen.dart';
import 'package:explorer_os_mobile/features/home/presentation/home_screen.dart';
import 'package:explorer_os_mobile/features/maps/presentation/maps_screen.dart';
import 'package:explorer_os_mobile/features/profile/presentation/profile_screen.dart';
import 'package:explorer_os_mobile/features/radio/presentation/radio_screen.dart';
import 'package:explorer_os_mobile/features/settings/presentation/settings_screen.dart';
import 'package:explorer_os_mobile/features/stories/presentation/stories_screen.dart';
import 'package:explorer_os_mobile/features/wildlife/presentation/wildlife_screen.dart';

/// Central navigation configuration.
///
/// Uses `go_router` with a [StatefulShellRoute] — the modern pattern for
/// bottom-navigation apps where each tab keeps its own navigation stack. The
/// visual shell (the `NavigationBar`) lives in `AppShell`; this file wires the
/// tab branches and the pushed detail routes to it. Detail routes are declared
/// outside the shell so they open full-screen (no bottom bar).
class AppRouter {
  const AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoute.home.path,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          _branch(AppRoute.home.path, const HomeScreen()),
          _branch(AppRoute.explore.path, const DestinationsScreen()),
          _branch(AppRoute.map.path, const MapsScreen()),
          _branch(AppRoute.radio.path, const RadioScreen()),
          _branch(AppRoute.profile.path, const ProfileScreen()),
        ],
      ),
      _route(AppRoute.settings.path, const SettingsScreen()),
      _route(AppRoute.downloads.path, const DownloadsScreen()),
      _route(AppRoute.stories.path, const StoriesScreen()),
      _route(AppRoute.wildlife.path, const WildlifeScreen()),
      _route(AppRoute.gps.path, const GpsScreen()),
      GoRoute(
        path: AppRoute.destinationDetails.path,
        builder: (context, state) => DestinationDetailsScreen(
          destinationId: state.pathParameters['id'] ?? '',
        ),
      ),
    ],
  );

  static StatefulShellBranch _branch(String path, Widget child) =>
      StatefulShellBranch(
        routes: [GoRoute(path: path, builder: (context, state) => child)],
      );

  static GoRoute _route(String path, Widget child) =>
      GoRoute(path: path, builder: (context, state) => child);
}
