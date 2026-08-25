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
import 'package:explorer_os_mobile/features/discover_home/presentation/discover_event_link_screen.dart';
import 'package:explorer_os_mobile/features/discover_home/presentation/discover_home_screen.dart';
import 'package:explorer_os_mobile/features/explore/presentation/explore_home_screen.dart';
import 'package:explorer_os_mobile/features/explore/presentation/explorer_mode_screen.dart';
import 'package:explorer_os_mobile/features/around_me/presentation/around_me_screen.dart';
import 'package:explorer_os_mobile/features/around_me/presentation/gps_debug_screen.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/marion_discovery_screen.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/nearby_places_screen.dart';
import 'package:explorer_os_mobile/features/discovery/presentation/discovery_categories_screen.dart';
import 'package:explorer_os_mobile/features/downloads/presentation/downloads_screen.dart';
import 'package:explorer_os_mobile/features/home/presentation/home_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/adventure_map_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/guide_home_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/guide_intro_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/mission_complete_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/mission_intro_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/mission_player_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/mission_puzzle_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/missions_home_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/old_world_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/player_discoveries_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/qr_scan_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/treasure_map_panel_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/treasure_map_screen.dart';
import 'package:explorer_os_mobile/features/more/presentation/more_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/ocala_forest_screen.dart';
import 'package:explorer_os_mobile/features/profile/presentation/profile_screen.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';
import 'package:explorer_os_mobile/features/radio/presentation/i_see_something_screen.dart';
import 'package:explorer_os_mobile/features/radio/presentation/local_gems_screen.dart';
import 'package:explorer_os_mobile/features/radio/presentation/radio_screen.dart';
import 'package:explorer_os_mobile/features/radio/presentation/station_selection_screen.dart';
import 'package:explorer_os_mobile/features/radio/presentation/tell_me_more_screen.dart';
import 'package:explorer_os_mobile/features/radio_director/presentation/radio_director_debug_page.dart';
import 'package:explorer_os_mobile/features/programming_director/presentation/programming_director_console_page.dart';
import 'package:explorer_os_mobile/features/settings/presentation/settings_screen.dart';
import 'package:explorer_os_mobile/features/stories/presentation/stories_screen.dart';
import 'package:explorer_os_mobile/features/what_is_that/presentation/what_is_that_screen.dart';
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
    // Adventure-first: the app lands directly on the Adventures storefront,
    // never a general map or a recommendation feed.
    initialLocation: AppRoute.missionsHome.path,
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
      if (atAuth) return AppRoute.missionsHome.path;
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        // Adventure-first: exactly three primary tabs, in this order:
        // Adventures (the adventure storefront/landing screen), Map (the
        // active adventure's game board, or the general explore map when
        // none is active), My Discoveries (the player's journal). Branch
        // order MUST match the nav bar in AppShell. Radio, Discover's
        // recommendation feed, Wildlife Guide, and everything else live one
        // tap away via More (see the pushed routes below) — same demotion
        // mechanism this router already used before this change, just
        // applied to a different set of screens.
        branches: [
          _branch(AppRoute.missionsHome.path, const MissionsHomeScreen()),
          _branch(AppRoute.map.path, const AdventureMapScreen()),
          _branch(AppRoute.guideHome.path, const GuideHomeScreen()),
          _branch(AppRoute.myDiscoveries.path, const PlayerDiscoveriesScreen()),
        ],
      ),
      // Authentication (outside the tab shell).
      _route(AppRoute.welcome.path, const WelcomeScreen()),
      _route(AppRoute.signIn.path, const SignInScreen()),
      _route(AppRoute.createAccount.path, const CreateAccountScreen()),
      _route(AppRoute.forgotPassword.path, const ForgotPasswordScreen()),

      // Pushed / full-screen routes reachable from More and links. Radio,
      // Discover's recommendation feed, and Wildlife Guide live here (out of
      // the primary shell branches, which are now Adventures/Map/My
      // Discoveries) — all three screens are otherwise completely
      // unchanged, still one tap away via More or the persistent mini-player.
      _route(AppRoute.radio.path, const RadioScreen()),
      _route(AppRoute.discoverHome.path, const DiscoverHomeScreen()),
      _route(AppRoute.wildlife.path, const WildlifeScreen()),
      _route(AppRoute.more.path, const MoreScreen()),
      _route(AppRoute.placesGuide.path, const ExploreHomeScreen()),
      _route(AppRoute.stories.path, const StoriesScreen()),
      _route(AppRoute.aroundMe.path, const AroundMeScreen()),
      _route(AppRoute.aiRanger.path, const AiRangerScreen()),
      _route(AppRoute.explorerMode.path, const ExplorerModeScreen()),
      _route(AppRoute.iSeeSomething.path, const ISeeSomethingScreen()),
      _route(AppRoute.whatIsThat.path, const WhatIsThatScreen()),
      _route(AppRoute.ocalaForest.path, const OcalaForestScreen()),
      _route(AppRoute.localGems.path, const LocalGemsScreen()),
      GoRoute(
        path: AppRoute.tellMeMore.path,
        builder: (context, state) => TellMeMoreScreen(
          tellMeMoreContext: state.extra is TellMeMoreContext
              ? state.extra as TellMeMoreContext
              : null,
        ),
      ),
      _route(AppRoute.stationSelect.path, const StationSelectionScreen()),
      _route(AppRoute.home.path, const HomeScreen()),
      _route(AppRoute.discover.path, const DiscoveryCategoriesScreen()),
      _route(AppRoute.discoverArea.path, const MarionDiscoveryScreen()),
      _route(AppRoute.nearbyPlaces.path, const NearbyPlacesScreen()),
      _route(AppRoute.profile.path, const ProfileScreen()),
      _route(AppRoute.settings.path, const SettingsScreen()),
      _route(AppRoute.downloads.path, const DownloadsScreen()),
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
      // The push-notification deep link target — always opens the exact
      // event, never the generic Discover home (spec: "Notification ->
      // Deep Link -> Open Event").
      GoRoute(
        path: AppRoute.discoverEventDetail.path,
        builder: (context, state) => DiscoverEventLinkScreen(
          eventId: state.pathParameters['id'] ?? '',
        ),
      ),

      // Marion County Adventures detail/gameplay routes. missionsHome
      // itself is now the Adventures primary tab (see the shell branches
      // above); everything below stays a pushed route reached from it.
      _route(AppRoute.guideIntro.path, const GuideIntroScreen()),
      GoRoute(
        path: AppRoute.missionIntro.path,
        builder: (context, state) => MissionIntroScreen(
          missionId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoute.missionPlayer.path,
        builder: (context, state) => MissionPlayerScreen(
          missionId: state.pathParameters['id'] ?? '',
        ),
      ),
      _route(AppRoute.qrScan.path, const QrScanScreen()),
      _route(AppRoute.treasureMap.path, const TreasureMapScreen()),
      GoRoute(
        path: AppRoute.oldWorld.path,
        builder: (context, state) => OldWorldScreen(
          oldWorldId: state.pathParameters['id'] ?? '',
          missionComplete: state.extra == true,
        ),
      ),
      _route(AppRoute.missionPuzzle.path, const MissionPuzzleScreen()),
      _route(AppRoute.missionComplete.path, const MissionCompleteScreen()),
      GoRoute(
        path: AppRoute.missionDiscoveries.path,
        builder: (context, state) => TreasureMapPanelScreen(
          missionId: state.pathParameters['id'] ?? '',
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
