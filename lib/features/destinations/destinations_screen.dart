import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// The Destinations tab.
///
/// This is where the read-only list of ExplorerOS destinations (fetched from
/// the backend) will be displayed. Phase 1 keeps it as a placeholder so we do
/// NOT hardcode any destination data. In a later phase, this screen will watch
/// a Riverpod provider that loads destinations from `SupabaseService` and
/// render them with `LoadingWidget` / `ErrorView` for the async states.
class DestinationsScreen extends StatelessWidget {
  const DestinationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Destinations')),
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.explore_outlined,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: AppConstants.spacingMd),
            Text('Destinations', style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              'Destination content will load here from the backend.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
