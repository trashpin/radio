import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// A reusable "Coming Soon" placeholder.
///
/// Phase 1 intentionally ships several tabs (Map, Radio) before their real
/// features (Offline Maps, Explorer Radio) are built. Rather than duplicating
/// placeholder markup, each not-yet-built screen renders this single widget.
/// When a feature is implemented later, we simply swap this out for the real
/// screen — the navigation and routing stay untouched.
class ComingSoonView extends StatelessWidget {
  const ComingSoonView({super.key, this.featureName, this.icon});

  /// Optional feature label (e.g. "Map", "Radio") shown above the message.
  final String? featureName;

  /// Optional icon representing the upcoming feature.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? Icons.hourglass_empty_rounded,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppConstants.spacingMd),
          if (featureName != null)
            Text(featureName!, style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            'Coming Soon',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
