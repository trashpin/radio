import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/shared/components/app_card.dart';

/// A large, tappable dashboard tile: a solid icon chip, a title, a two-line
/// subtitle, and a trailing affordance (chevron by default).
///
/// The primary building block of the Home dashboard. Composes the shared
/// [AppCard] (white surface, soft shadow, press animation) so every dashboard
/// entry looks and behaves identically — satisfying the "large cards, minimal
/// clutter" design goal. The [accent] controls the icon-chip color so cards can
/// be subtly differentiated, and [trailing] lets special cards (e.g. Explorer
/// Radio) show a play button instead of a chevron.
class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.accent,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// Icon-chip background color (defaults to the brand primary).
  final Color? accent;

  /// Optional trailing widget (defaults to a chevron).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          _IconChip(icon: icon, color: accent ?? theme.colorScheme.primary),
          const Gap.h(AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const Gap.v(AppSpacing.xs),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Gap.h(AppSpacing.md),
          trailing ??
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
        ],
      ),
    );
  }
}

/// Solid rounded-square icon chip (colored background, white glyph) matching the
/// premium dashboard style.
class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.mdAll),
      child: Icon(icon, color: AppColors.textOnPrimary, size: 28),
    );
  }
}
