import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';

/// A polished placeholder for features that are prepared but not yet built
/// (GPS, Radio, Stories, Wildlife, Downloads, Maps).
///
/// Instead of a bare "Coming Soon" label, this presents the upcoming feature
/// premium-style: a large gradient icon medallion, the feature name, a "Coming
/// soon" badge, and a one-line description of what it will do. Reusing one
/// component keeps every not-yet-built screen consistent, and swapping in the
/// real feature later is a one-line change in the router.
class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: AppRadius.xlAll,
              ),
              child: Icon(icon, size: 52, color: AppColors.textOnPrimary),
            ),
            const Gap.v(AppSpacing.xl),
            Text(title, style: theme.textTheme.headlineLarge),
            const Gap.v(AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: AppRadius.pillAll,
              ),
              child: Text(
                'Coming soon',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            const Gap.v(AppSpacing.lg),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
