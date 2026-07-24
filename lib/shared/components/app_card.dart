import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_durations.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_shadows.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';

/// The foundational surface for ExplorerOS.
///
/// Every card-like surface in the app is built on [AppCard] so padding, corner
/// radius, background, soft shadow, and the subtle press animation are all
/// consistent and defined in ONE place (pulling from the design-system tokens).
/// Higher-level cards (e.g. `DashboardCard`) compose this widget.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.gradient,
    this.color,
    this.borderRadius = AppRadius.lgAll,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Optional gradient background (used by feature/highlight cards). When null,
  /// [color] (or the theme surface) is used.
  final Gradient? gradient;
  final Color? color;
  final BorderRadius borderRadius;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = widget.gradient == null
        ? (widget.color ?? theme.colorScheme.surface)
        : null;

    // Subtle scale-down feedback on press (premium tactile feel).
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: AppDurations.fast,
      curve: AppDurations.standardCurve,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            gradient: widget.gradient,
            borderRadius: widget.borderRadius,
            boxShadow: AppShadows.card,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: widget.borderRadius,
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
