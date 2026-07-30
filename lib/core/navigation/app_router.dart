import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/navigation/app_shell.dart';
import 'package:explorer_os_mobile/features/auth/auth_controller.dart';
import 'package:explorer_os_mobile/features/auth/presentation/create_account_screen.dart';
import 'package:explorer_os_mobile/features/auth/presentation/forgot_password_screen.dart';
import 'package:explorer_os_mobile/features/auth/presentation/sign_in_screen.dart';
import 'package:explorer_os_mobile/features/auth/presentation/welcome_screen.dart';
import 'package:explorer_os_mobile/features/companion/presentation/ai_ranger_screen.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/destination_details_screen.dart';
import 'package:explorer_os_mobile/features/explore/presentation/explore_home_screen.dart';
import 'package:explorer_os_mobile/features/around_me/presentation/around_me_screen.dart';
import 'package:explorer_os_mobile/features/around_me/presentation/gps_debug_screen.dart';
import 'package:explorer_os_mobile/features/discovery/presentation/discovery_categories_screen.dart';
import 'package:explorer_os_mobile/features/downloads/presentation/downloads_screen.dart';
import 'package:explorer_os_mobile/features/home/presentation/home_screen.dart';
import 'package:explorer_os_mobile/features/maps/presentation/maps_screen.dart';
import 'package:explorer_os_mobile/features/more/presentation/more_screen.dart';
import 'package:explorer_os_mobile/features/profile/presentation/profile_screen.dart';
import 'package:explorer_os_mobile/features/radio/presentation/radio_screen.dart';
import 'package:explorer_os_mobile/features/radio_director/presentation/radio_director_debug_page.dart';
import 'package:explorer_os_mobile/features/programming_director/presentation/programming_director_console_page.dart';
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
    initialLocation: AppRoute.explore.path,
    // Re-run [redirect] whenever auth state changes (sign in/out, guest).
    refreshListenable: authController,
    // Auth gate: require sign-in or guest before entering the app. When there's
    // no backend configured, the app is open (demo/offline).
    redirect: (context, state) {
      if (!authController.ready) return null;
      final loc = state.matchedLocation;
      const authPaths = {
        '/welcome',
        '/sign-in',
        '/create-account',
        '/forgot-password',
      };
      final atAuth = authPaths.contains(loc);
      if (!authController.canEnter) {
        return atAuth ? null : AppRoute.welcome.path;
      }
      // Already signed in / guest — don't sit on an auth screen.
      if (atAuth) return AppRoute.explore.path;
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        // Branch order MUST match the nav bar in AppShell:
        // Radio, Explore, Map, Stories, More.
        branches: [
          _branch(AppRoute.radio.path, const RadioScreen()),
          _branch(AppRoute.explore.path, const ExploreHomeScreen()),
          _branch(AppRoute.map.path, const MapsScreen()),
          _branch(AppRoute.stories.path, const StoriesScreen()),
          _branch(AppRoute.more.path, const MoreScreen()),
        ],
      ),
      // Authentication (outside the tab shell).
      _route(AppRoute.welcome.path, const WelcomeScreen()),
      _route(AppRoute.signIn.path, const SignInScreen()),
      _route(AppRoute.createAccount.path, const CreateAccountScreen()),
      _route(AppRoute.forgotPassword.path, const ForgotPasswordScreen()),

      // Pushed / full-screen routes reachable from Explore, More, and links.
      _route(AppRoute.aroundMe.path, const AroundMeScreen()),
      _route(AppRoute.aiRanger.path, const AiRangerScreen()),
      _route(AppRoute.home.path, const HomeScreen()),
      _route(AppRoute.discover.path, const DiscoveryCategoriesScreen()),
      _route(AppRoute.profile.path, const ProfileScreen()),
      _route(AppRoute.settings.path, const SettingsScreen()),
      _route(AppRoute.downloads.path, const DownloadsScreen()),
      _route(AppRoute.wildlife.path, const WildlifeScreen()),
      _route(AppRoute.gps.path, const GpsDebugScreen()),
      _route(AppRoute.radioDirector.path, const RadioDirectorDebugPage()),
      _route(AppRoute.programmingDirector.path,
          const ProgrammingDirectorConsolePage()),
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
