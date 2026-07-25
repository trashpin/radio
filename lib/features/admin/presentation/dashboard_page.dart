import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/admin_connection.dart';
import 'package:explorer_os_mobile/features/admin/admin_stats.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';

/// Admin dashboard: KPI widgets, recent content, storage, and publish queue.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(adminStatsProvider);
    final stats = statsAsync.value ?? const AdminStats();

    final cards = <Widget>[
      AdminStatCard(
          label: 'Parks', value: '${stats.parks}', icon: Icons.forest_rounded),
      AdminStatCard(
          label: 'Locations',
          value: '${stats.locations}',
          icon: Icons.place_rounded,
          tint: const Color(0xFF2C6E8F)),
      AdminStatCard(
          label: 'Stories',
          value: '${stats.stories}',
          icon: Icons.menu_book_rounded,
          tint: const Color(0xFF6A5ACD)),
      AdminStatCard(
          label: 'Songs',
          value: '${stats.songs}',
          icon: Icons.library_music_rounded,
          tint: const Color(0xFFE0A458)),
      AdminStatCard(
          label: 'Wildlife',
          value: '${stats.wildlife}',
          icon: Icons.pets_rounded,
          tint: const Color(0xFF2E9E6B)),
      AdminStatCard(
          label: 'Media files',
          value: '${stats.media}',
          icon: Icons.perm_media_rounded,
          tint: const Color(0xFF2C6E8F)),
      AdminStatCard(
          label: 'Published',
          value: '${stats.published}',
          icon: Icons.check_circle_rounded,
          tint: const Color(0xFF2E7D32)),
      AdminStatCard(
          label: 'Drafts',
          value: '${stats.drafts}',
          icon: Icons.edit_note_rounded,
          tint: const Color(0xFF8A6D00)),
      AdminStatCard(
          label: 'Pending review',
          value: '${stats.pendingReview}',
          icon: Icons.rate_review_rounded,
          tint: const Color(0xFF2C6E8F)),
      AdminStatCard(
          label: 'Downloads',
          value: '${stats.downloads}',
          icon: Icons.download_rounded),
      AdminStatCard(
          label: 'Subscribers',
          value: '${stats.subscribers}',
          icon: Icons.card_membership_rounded,
          tint: const Color(0xFF6A5ACD)),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Dashboard',
          subtitle: 'ExplorerOS content at a glance',
          actions: [
            FilledButton.icon(
              onPressed: () => ref.invalidate(adminStatsProvider),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.xl),
        const _ConnectionPanel(),
        const Gap.v(AppSpacing.xl),
        if (statsAsync.isLoading) const LinearProgressIndicator(),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 1200
                ? 4
                : constraints.maxWidth >= 820
                    ? 3
                    : constraints.maxWidth >= 520
                        ? 2
                        : 1;
            const gap = AppSpacing.lg;
            final cardWidth =
                (constraints.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final c in cards)
                  SizedBox(width: cardWidth, child: c),
              ],
            );
          },
        ),
        const Gap.v(AppSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final recent = _RecentContent();
            final side = Column(
              children: const [
                _StoragePanel(),
                Gap.v(AppSpacing.lg),
                _ActivityPanel(),
              ],
            );
            if (!wide) {
              return Column(
                children: [recent, const Gap.v(AppSpacing.lg), side],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: recent),
                const Gap.h(AppSpacing.lg),
                Expanded(flex: 2, child: side),
              ],
            );
          },
        ),
        const Gap.v(AppSpacing.xxl),
      ],
    );
  }
}

/// Live Supabase connection health: prompts for missing config, warns about an
/// unsafe (secret) key, and shows per-table/bucket status.
class _ConnectionPanel extends ConsumerWidget {
  const _ConnectionPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(adminConnectionProvider);

    return AdminSectionCard(
      child: async.when(
        loading: () => const Row(
          children: [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            Gap.h(AppSpacing.md),
            Text('Checking Supabase connection…'),
          ],
        ),
        error: (e, _) => _banner(
          theme,
          Icons.error_outline_rounded,
          const Color(0xFFC0392B),
          'Connection check failed',
          '$e',
        ),
        data: (report) {
          if (!report.configured) {
            return _banner(
              theme,
              Icons.link_off_rounded,
              const Color(0xFF8A6D00),
              'Not connected to Supabase',
              'Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (the sb_publishable_ '
                  'anon key) so the admin reads live data.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    report.allOk
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    color: report.allOk
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFF8A6D00),
                    size: 20,
                  ),
                  const Gap.h(AppSpacing.sm),
                  Text('Supabase connection',
                      style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Re-check',
                    onPressed: () => ref.invalidate(adminConnectionProvider),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                ],
              ),
              if (report.keyWarning != null) ...[
                const Gap.v(AppSpacing.sm),
                _banner(theme, Icons.lock_outline_rounded,
                    const Color(0xFF8A6D00), 'Unsafe key', report.keyWarning!),
              ],
              const Gap.v(AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final c in report.checks)
                    _CheckChip(
                      label: c.name,
                      ok: c.ok,
                      kind: c.kind,
                      detail: c.detail,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _banner(ThemeData theme, IconData icon, Color color, String title,
      String message) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const Gap.h(AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({
    required this.label,
    required this.ok,
    required this.kind,
    required this.detail,
  });

  final String label;
  final bool ok;
  final CheckKind kind;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final color = ok ? const Color(0xFF2E7D32) : const Color(0xFFC0392B);
    return Tooltip(
      message: detail,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: AppRadius.pillAll,
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              kind == CheckKind.bucket
                  ? Icons.folder_rounded
                  : Icons.table_rows_rounded,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(ok ? Icons.check_rounded : Icons.close_rounded,
                size: 13, color: color),
          ],
        ),
      ),
    );
  }
}

/// Recently added content, reusing the destinations list.
class _RecentContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = ref.watch(destinationsProvider).value ?? const [];
    final recent = items.take(6).toList();
    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recently added content',
              style: theme.textTheme.titleMedium),
          const Gap.v(AppSpacing.md),
          if (recent.isEmpty)
            const AdminEmptyState(message: 'No content yet.')
          else
            for (final d in recent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Icon(Icons.forest_rounded,
                          size: 18, color: theme.colorScheme.primary),
                    ),
                    const Gap.h(AppSpacing.md),
                    Expanded(
                      child: Text(d.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    StatusBadge(d.featured
                        ? BadgeStatus.published
                        : BadgeStatus.draft),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _StoragePanel extends ConsumerWidget {
  const _StoragePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(adminStatsProvider).value ?? const AdminStats();
    // Rough estimate for the widget; real usage comes from Storage metadata.
    final approxMb = stats.media * 4;
    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Storage usage', style: theme.textTheme.titleMedium),
          const Gap.v(AppSpacing.md),
          ClipRRect(
            borderRadius: AppRadius.pillAll,
            child: LinearProgressIndicator(
              value: (approxMb / 1024).clamp(0.02, 1.0),
              minHeight: 8,
            ),
          ),
          const Gap.v(AppSpacing.sm),
          Text('${stats.media} media files · ~$approxMb MB',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick publish queue', style: theme.textTheme.titleMedium),
          const Gap.v(AppSpacing.md),
          Row(
            children: [
              const StatusBadge(BadgeStatus.draft),
              const Gap.h(AppSpacing.sm),
              Expanded(
                child: Text('Drafts awaiting publish',
                    style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
