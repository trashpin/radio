import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/constants/app_constants.dart';
import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/core/utils/greeting.dart';
import 'package:explorer_os_mobile/features/home/presentation/widgets/info_placeholder_card.dart';
import 'package:explorer_os_mobile/shared/components/dashboard_card.dart';
import 'package:explorer_os_mobile/shared/components/hero_header.dart';
import 'package:explorer_os_mobile/shared/components/section_header.dart';

/// The Home screen — the dashboard of ExplorerOS.
///
/// This is the app's command center. It's assembled entirely from reusable
/// shared components ([HeroHeader], [DashboardCard], [SectionHeader],
/// [InfoPlaceholderCard]) and design-system tokens, so it stays declarative and
/// free of hardcoded styling. Cards navigate via `go_router` to the relevant
/// tabs/features; several are placeholders wired for features arriving next.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final greeting = greetingForTime(DateTime.now());

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          HeroHeader(
            greeting: greeting,
            title: AppConstants.appName,
            subtitle: AppConstants.appTagline,
          ),
          Padding(
            padding: AppSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Continue ---------------------------------------------
                const SectionHeader(title: 'Continue'),
                DashboardCard(
                  icon: Icons.play_circle_outline_rounded,
                  title: 'Continue Journey',
                  subtitle: 'Pick up where you left off',
                  onTap: () => context.go(AppRoute.explore.path),
                ),
                const Gap.v(AppSpacing.xxl),

                // --- Discover ---------------------------------------------
                const SectionHeader(title: 'Discover'),
                DashboardCard(
                  icon: Icons.explore_outlined,
                  title: 'Start Exploring',
                  subtitle: 'Browse every ExplorerOS destination',
                  onTap: () => context.go(AppRoute.explore.path),
                ),
                const Gap.v(AppSpacing.lg),
                DashboardCard(
                  icon: Icons.near_me_outlined,
                  title: "What's Nearby",
                  subtitle: 'Points of interest around you',
                  onTap: () => context.go(AppRoute.map.path),
                ),
                const Gap.v(AppSpacing.xxl),

                // --- Listen & Save ----------------------------------------
                const SectionHeader(title: 'Listen & Save'),
                DashboardCard(
                  icon: Icons.radio_rounded,
                  title: 'Explorer Radio',
                  subtitle: 'Ranger stories and live audio guides',
                  gradient: AppColors.sunsetGradient,
                  onTap: () => context.go(AppRoute.radio.path),
                ),
                const Gap.v(AppSpacing.lg),
                DashboardCard(
                  icon: Icons.download_outlined,
                  title: 'Downloads',
                  subtitle: 'Take maps and guides offline',
                  onTap: () => context.push(AppRoute.downloads.path),
                ),
                const Gap.v(AppSpacing.xxl),

                // --- Today (live data coming soon) ------------------------
                const SectionHeader(title: 'Today'),
                const InfoPlaceholderCard(
                  icon: Icons.wb_sunny_outlined,
                  title: 'Weather',
                  message: 'Live conditions for your destination will appear '
                      'here.',
                ),
                const Gap.v(AppSpacing.lg),
                const InfoPlaceholderCard(
                  icon: Icons.history_rounded,
                  title: 'Recent Activity',
                  message: 'Your recent stops and saved places will show up '
                      'here.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
