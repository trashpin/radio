import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';

/// The dashboard hero content block (menu/bell bar, brand logo, product name,
/// personalized greeting, and prompt).
///
/// Purely presentational and designed to sit ON TOP of the full-bleed hero
/// photograph provided by the Home screen — hence all text is white with no
/// background of its own. The greeting string is computed by a `core/utils`
/// helper and passed in, keeping time/user logic out of the widget.
class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.title,
    required this.greeting,
    required this.prompt,
    this.onMenu,
    this.onNotifications,
  });

  final String title;
  final String greeting;
  final String prompt;
  final VoidCallback? onMenu;
  final VoidCallback? onNotifications;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onImage = AppColors.textOnPrimary;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        child: Column(
          children: [
            // Top bar: menu (left) + notifications (right).
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CircleIconButton(
                  icon: Icons.menu_rounded,
                  onPressed: onMenu,
                  tooltip: 'Menu',
                ),
                _CircleIconButton(
                  icon: Icons.notifications_none_rounded,
                  onPressed: onNotifications,
                  tooltip: 'Notifications',
                ),
              ],
            ),
            const Gap.v(AppSpacing.xl),
            // Brand logo mark.
            const Icon(Icons.terrain_rounded, color: onImage, size: 46),
            const Gap.v(AppSpacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.displayLarge?.copyWith(color: onImage),
            ),
            const Gap.v(AppSpacing.sm),
            Text(
              greeting,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: AppColors.heroAccent),
            ),
            const Gap.v(AppSpacing.xs),
            Text(
              prompt,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: onImage.withValues(alpha: 0.9)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A translucent circular icon button used for the hero's menu/bell actions so
/// they stay tappable and legible over the photograph.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: AppColors.textOnPrimary),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.18),
      ),
    );
  }
}
