import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';

/// A KPI tile for the dashboard: icon chip, large value, and label.
class AdminStatCard extends StatelessWidget {
  const AdminStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tint,
    this.hint,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? tint;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tint ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              if (hint != null)
                Text(hint!, style: theme.textTheme.bodySmall),
            ],
          ),
          const Gap.v(AppSpacing.md),
          Text(value,
              style: theme.textTheme.headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const Gap.v(AppSpacing.xs),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Content lifecycle badge (published / draft / review / etc.).
enum BadgeStatus { published, draft, review, planned, error }

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.label});

  final BadgeStatus status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (status) {
      BadgeStatus.published => (const Color(0xFF2E7D32), 'Published'),
      BadgeStatus.draft => (const Color(0xFF8A6D00), 'Draft'),
      BadgeStatus.review => (const Color(0xFF2C6E8F), 'In review'),
      BadgeStatus.planned => (const Color(0xFF6A5ACD), 'Planned'),
      BadgeStatus.error => (const Color(0xFFC0392B), 'Error'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label ?? text,
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Page title + subtitle + optional trailing actions.
class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineLarge),
              if (subtitle != null) ...[
                const Gap.v(AppSpacing.xs),
                Text(subtitle!, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        ...actions,
      ],
    );
  }
}

/// Rounded surface used to wrap tables/panels.
class AdminSectionCard extends StatelessWidget {
  const AdminSectionCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: child,
    );
  }
}

/// Consistent empty-state panel.
class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.inbox_rounded,
              size: 40, color: theme.disabledColor),
          const Gap.v(AppSpacing.md),
          Text(message, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
