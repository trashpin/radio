import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';

/// The app's large primary call-to-action button.
///
/// Wraps Material's `FilledButton` (whose size/shape defaults come from the
/// theme) so call sites get a consistent, large, pill-shaped CTA with an
/// optional leading [icon] — without repeating styling.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return FilledButton(onPressed: onPressed, child: Text(label));
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: Text(label),
      ),
    );
  }
}
