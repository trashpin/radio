import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/shared/components/app_card.dart';

/// The Profile tab.
///
/// Shows a premium profile header and a menu that links to Settings plus the
/// prepared feature areas (Stories, Wildlife, GPS). Built from shared
/// components so it matches the rest of the app. These entries also make the
/// prepared pushed routes reachable in the UI today.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoute.settings.path),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: const [
          _ProfileHeader(name: 'Explorer'),
          Gap.v(AppSpacing.xxl),
          _MenuTile(
            icon: Icons.auto_stories_rounded,
            title: 'Stories',
            route: AppRoute.stories,
          ),
          Gap.v(AppSpacing.lg),
          _MenuTile(
            icon: Icons.pets_rounded,
            title: 'Wildlife',
            route: AppRoute.wildlife,
          ),
          Gap.v(AppSpacing.lg),
          _MenuTile(
            icon: Icons.gps_fixed_rounded,
            title: 'GPS Guidance',
            route: AppRoute.gps,
          ),
          Gap.v(AppSpacing.lg),
          _MenuTile(
            icon: Icons.settings_outlined,
            title: 'Settings',
            route: AppRoute.settings,
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Icon(Icons.person_rounded,
                size: 36, color: theme.colorScheme.primary),
          ),
          const Gap.h(AppSpacing.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.headlineMedium),
              const Gap.v(AppSpacing.xs),
              Text('Tap to edit your profile',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.route,
  });

  final IconData icon;
  final String title;
  final AppRoute route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      onTap: () => context.push(route.path),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const Gap.h(AppSpacing.lg),
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
