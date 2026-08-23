import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';

/// The "More" tab — a menu for the sections that don't have a dedicated tab
/// (Radio, Explore, Stories, Downloads, Profile, Settings). Wildlife Guide
/// moved out of here to its own primary tab; Explore and Stories moved in
/// when they were removed from the primary bottom navigation, and Radio
/// joined them when Discover took its place (their screens are unchanged —
/// only the entry point moved; Radio is also reachable via Discover's
/// persistent mini player).
///
/// Keeps the primary nav focused on the four core experiences while remaining
/// a single tap from everything else.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_MoreItem>[
      const _MoreItem(Icons.podcasts_rounded, 'Radio', AppRoute.radio),
      const _MoreItem(Icons.explore_rounded, 'Explore', AppRoute.explore),
      const _MoreItem(Icons.menu_book_rounded, 'Stories', AppRoute.stories),
      const _MoreItem(Icons.travel_explore_rounded, 'Discover This Area', AppRoute.discoverArea),
      const _MoreItem(Icons.download_rounded, 'Downloads', AppRoute.downloads),
      const _MoreItem(Icons.person_rounded, 'Profile', AppRoute.profile),
      const _MoreItem(Icons.settings_rounded, 'Settings', AppRoute.settings),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView.separated(
        padding: AppSpacing.screenPadding,
        itemCount: items.length,
        separatorBuilder: (_, _) => const Gap.v(AppSpacing.md),
        itemBuilder: (context, i) {
          final item = items[i];
          final theme = Theme.of(context);
          return Material(
            color: theme.colorScheme.surface,
            borderRadius: AppRadius.lgAll,
            child: ListTile(
              shape:
                  const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
              leading: Icon(item.icon, color: theme.colorScheme.primary),
              title: Text(item.label, style: theme.textTheme.titleMedium),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(item.route.path),
            ),
          );
        },
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem(this.icon, this.label, this.route);
  final IconData icon;
  final String label;
  final AppRoute route;
}
