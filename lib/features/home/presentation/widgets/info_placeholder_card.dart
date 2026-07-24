import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/shared/components/app_card.dart';

/// A compact "not built yet" info tile used for the dashboard's Weather and
/// Recent Activity placeholders.
///
/// Distinct from [DashboardCard] (which is an actionable navigation tile): this
/// simply reserves the space and communicates that live data is coming, so the
/// dashboard layout is already final. Built on [AppCard] for visual
/// consistency.
class InfoPlaceholderCard extends StatelessWidget {
  const InfoPlaceholderCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(icon,
                    size: 20, color: theme.colorScheme.primary),
              ),
              const Gap.h(AppSpacing.md),
              Text(title, style: theme.textTheme.titleMedium),
            ],
          ),
          const Gap.v(AppSpacing.md),
          Text(message, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
