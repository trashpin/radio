import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';

/// The large gradient "hero" welcome area at the top of the dashboard.
///
/// Provides the premium first impression: a full-bleed gradient panel with a
/// greeting, the product name, and a short tagline. Purely presentational — the
/// greeting string is computed by a `core/utils` helper and passed in, keeping
/// logic out of the widget.
class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.greeting,
    required this.title,
    required this.subtitle,
  });

  final String greeting;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxxl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting,
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.textOnPrimary.withValues(alpha: 0.85),
            ),
          ),
          const Gap.v(AppSpacing.xs),
          Text(
            title,
            style: theme.textTheme.displayLarge
                ?.copyWith(color: AppColors.textOnPrimary),
          ),
          const Gap.v(AppSpacing.sm),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textOnPrimary.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}
