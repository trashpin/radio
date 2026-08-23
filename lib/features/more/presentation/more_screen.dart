import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';

/// The "More" screen — everything that isn't one of Sunshine Travel Radio's
/// two primary tabs (Explore = the radio player, Discover = things to do).
/// Reached via a menu item on Explore's own menu sheet and a button on
/// Discover's greeting header, not a bottom-nav tab of its own. Map and
/// Wildlife Guide moved in here when the primary nav was cut down to exactly
/// two tabs; their screens are unchanged, only the entry point moved.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <_MoreItem>[
      const _MoreItem(Icons.map_rounded, 'Map', AppRoute.map),
      const _MoreItem(Icons.pets_rounded, 'Wildlife Guide', AppRoute.wildlife),
      const _MoreItem(Icons.category_rounded, 'Places & Categories', AppRoute.placesGuide),
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
