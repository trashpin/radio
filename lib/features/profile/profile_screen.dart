import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import 'package:go_router/go_router.dart';

/// The Profile tab.
///
/// Phase 1 placeholder for the user's profile. It also hosts the entry point to
/// the Settings screen (Settings is not a bottom-nav tab, it is a pushed route),
/// demonstrating navigation between a tab and a detail screen via go_router.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
            const SizedBox(height: AppConstants.spacingMd),
            Text('Explorer', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              'Your profile details will appear here.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
