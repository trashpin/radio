import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/shared/components/app_card.dart';

/// A large, tappable dashboard tile (icon + title + subtitle + chevron).
///
/// This is the primary building block of the Home dashboard. It composes
/// [AppCard] and supports two looks:
///   • standard  → surface background, brand-colored icon chip
///   • featured  → a [gradient] background with white content (for highlights
///     like Explorer Radio)
///
/// Keeping this as one reusable component means every dashboard entry looks and
/// behaves identically, satisfying the "large cards, minimal clutter" goal.
class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.gradient,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// When set, the card uses this gradient and white content (featured style).
  final Gradient? gradient;

  /// Optional custom trailing widget (defaults to a chevron).
  final Widget? trailing;

  bool get _isFeatured => gradient != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor =
        _isFeatured ? AppColors.textOnPrimary : theme.colorScheme.onSurface;
    final subColor = _isFeatured
        ? AppColors.textOnPrimary.withValues(alpha: 0.85)
        : theme.textTheme.bodySmall?.color;

    return AppCard(
      onTap: onTap,
      gradient: gradient,
      child: Row(
        children: [
          _IconChip(icon: icon, featured: _isFeatured),
          const Gap.h(AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(color: onColor),
                ),
                const Gap.v(AppSpacing.xs),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: subColor),
                ),
              ],
            ),
          ),
          const Gap.h(AppSpacing.md),
          trailing ??
              Icon(
                Icons.chevron_right_rounded,
                color: onColor.withValues(alpha: 0.7),
              ),
        ],
      ),
    );
  }
}

/// The rounded icon chip shown on the leading edge of a [DashboardCard].
class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.featured});

  final IconData icon;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = featured
        ? AppColors.textOnPrimary.withValues(alpha: 0.18)
        : theme.colorScheme.primary.withValues(alpha: 0.12);
    final fg = featured ? AppColors.textOnPrimary : theme.colorScheme.primary;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.mdAll),
      child: Icon(icon, color: fg, size: 26),
    );
  }
}
