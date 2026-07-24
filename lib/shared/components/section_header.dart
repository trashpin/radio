import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';

/// A titled section header with an optional trailing action.
///
/// Reused above every dashboard section (e.g. "Continue", "Discover") to give
/// screens a consistent, uncluttered rhythm.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: theme.textTheme.headlineMedium),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
