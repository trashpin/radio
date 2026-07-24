import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// The Home tab — the landing screen of the app.
///
/// Phase 1 placeholder: it establishes the screen, its app bar, and the entry
/// point to Settings. Real content (featured destinations pulled from the
/// backend, etc.) will be added in later phases. It lives under
/// `features/home/` because the app is organized feature-first: each tab/flow
/// owns its own folder.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('${AppConstants.appName} Home'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome to ${AppConstants.appName}',
                style: theme.textTheme.headlineLarge),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              'Discover destinations and start exploring.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
