import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/core/constants/app_constants.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/shared/components/app_card.dart';

/// The Settings screen (pushed from Profile).
///
/// Placeholder settings plus a useful diagnostic: whether the Supabase backend
/// is configured. The backend status reads from [SupabaseService], keeping the
/// UI free of config logic.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = SupabaseService.isConfigured;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About', style: theme.textTheme.titleMedium),
                const Gap.v(AppSpacing.sm),
                Text(AppConstants.appName, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const Gap.v(AppSpacing.lg),
          AppCard(
            child: Row(
              children: [
                Icon(
                  connected
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  color: connected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const Gap.h(AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Backend connection',
                          style: theme.textTheme.titleMedium),
                      const Gap.v(AppSpacing.xs),
                      Text(
                        connected
                            ? 'Supabase configured'
                            : 'Not configured (set SUPABASE_URL / '
                                'SUPABASE_ANON_KEY)',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
