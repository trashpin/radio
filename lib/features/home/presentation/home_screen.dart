import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/constants/app_constants.dart';
import 'package:explorer_os_mobile/core/constants/asset_paths.dart';
import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/core/utils/greeting.dart';
import 'package:explorer_os_mobile/features/home/presentation/widgets/info_placeholder_card.dart';
import 'package:explorer_os_mobile/features/home/presentation/widgets/weather_card.dart';
import 'package:explorer_os_mobile/shared/components/dashboard_card.dart';
import 'package:explorer_os_mobile/shared/components/hero_header.dart';

/// The Home screen — the dashboard of ExplorerOS.
///
/// The app's command center, built entirely from reusable shared components
/// ([HeroHeader], [DashboardCard], [WeatherCard]) and design-system tokens, so
/// it stays declarative and free of hardcoded styling. A full-bleed hero
/// photograph forms the backdrop; white cards float over it. Cards navigate via
/// `go_router`; several show placeholder copy wired for features arriving next.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final greeting =
        '${greetingForTime(DateTime.now())}, ${AppConstants.placeholderExplorerName}';

    return Scaffold(
      body: Stack(
        children: [
          // Full-bleed hero photograph + legibility scrim (fixed background).
          const _HeroBackground(),
          // Scrolling content floating over the photo.
          ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              HeroHeader(
                title: AppConstants.appName,
                greeting: greeting,
                prompt: AppConstants.appHeroPrompt,
                onMenu: () {},
                onNotifications: () {},
              ),
              Padding(
                padding: AppSpacing.screenPaddingH,
                child: Column(
                  children: [
                    DashboardCard(
                      icon: Icons.play_arrow_rounded,
                      title: 'Continue Journey',
                      subtitle: 'Pick up where you left off',
                      onTap: () => context.go(AppRoute.explore.path),
                    ),
                    const Gap.v(AppSpacing.lg),
                    DashboardCard(
                      icon: Icons.explore_outlined,
                      title: 'Start Exploring',
                      subtitle: 'Browse destinations and plan your trip',
                      accent: AppColors.primaryDark,
                      onTap: () => context.go(AppRoute.explore.path),
                    ),
                    const Gap.v(AppSpacing.lg),
                    DashboardCard(
                      icon: Icons.location_on_outlined,
                      title: "What's Nearby?",
                      subtitle: 'See attractions around your location',
                      accent: AppColors.primaryLight,
                      onTap: () => context.go(AppRoute.map.path),
                    ),
                    const Gap.v(AppSpacing.lg),
                    DashboardCard(
                      icon: Icons.podcasts_rounded,
                      title: 'Explorer Radio',
                      subtitle: 'Ranger stories • Continue listening',
                      accent: AppColors.primaryDark,
                      trailing: const _RadioPlayButton(),
                      onTap: () => context.go(AppRoute.radio.path),
                    ),
                    const Gap.v(AppSpacing.lg),
                    DashboardCard(
                      icon: Icons.cloud_download_rounded,
                      title: 'Downloads',
                      subtitle: 'Take maps and guides offline',
                      onTap: () => context.push(AppRoute.downloads.path),
                    ),
                    const Gap.v(AppSpacing.lg),
                    const WeatherCard(),
                    const Gap.v(AppSpacing.lg),
                    const InfoPlaceholderCard(
                      icon: Icons.history_rounded,
                      title: 'Recent Activity',
                      message: 'Your recent stops and saved places will show '
                          'up here.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fixed hero background: the landscape photo with a subtle top/bottom scrim so
/// white hero text and floating cards stay legible.
class _HeroBackground extends StatelessWidget {
  const _HeroBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(AssetPaths.heroLandscape),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.35),
                Colors.black.withValues(alpha: 0.05),
                Colors.black.withValues(alpha: 0.25),
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

/// The pale circular "play" affordance shown on the Explorer Radio card.
class _RadioPlayButton extends StatelessWidget {
  const _RadioPlayButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.play_arrow_rounded, color: theme.colorScheme.primary),
    );
  }
}
