import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/events/event_discovery_repository.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';

/// The nightlife/time-of-day filter for the review queue (spec: "All
/// Events/Daytime/Evening/Nightlife/Live Music/Comedy/Karaoke/Dancing").
/// Karaoke isn't a Ticketmaster-derivable experience tag today (no source
/// has produced one yet), so it's omitted rather than added as a filter
/// that could never match anything.
enum _ReviewFilter { all, daytime, evening, nightlife, liveMusic, comedy, dancing }

extension on _ReviewFilter {
  String get label => switch (this) {
        _ReviewFilter.all => 'All events',
        _ReviewFilter.daytime => 'Daytime',
        _ReviewFilter.evening => 'Evening',
        _ReviewFilter.nightlife => 'Nightlife',
        _ReviewFilter.liveMusic => 'Live music',
        _ReviewFilter.comedy => 'Comedy',
        _ReviewFilter.dancing => 'Dancing',
      };

  bool matches(DiscoveredEventRow item) => switch (this) {
        _ReviewFilter.all => true,
        _ReviewFilter.daytime =>
          item.timeOfDay == 'morning' || item.timeOfDay == 'afternoon',
        _ReviewFilter.evening => item.isEveningOrLater,
        _ReviewFilter.nightlife => item.interestTags.contains('nightlife'),
        _ReviewFilter.liveMusic => item.interestTags.contains('live_music'),
        _ReviewFilter.comedy => item.experienceTags.contains('comedy'),
        _ReviewFilter.dancing => item.experienceTags.contains('dancing'),
      };
}

class _ReviewFilterNotifier extends Notifier<_ReviewFilter> {
  @override
  _ReviewFilter build() => _ReviewFilter.all;
  void select(_ReviewFilter f) => state = f;
}

final _reviewFilterProvider =
    NotifierProvider<_ReviewFilterNotifier, _ReviewFilter>(_ReviewFilterNotifier.new);

/// Admin -> Event Discovery: the multi-source pipeline's control room.
/// Shows each source's last-run stats (spec's "Found/New/Duplicates/Needs
/// Review/Rejected" summary) and an approval queue for every candidate the
/// engine hasn't published on its own — both low-confidence "needs review"
/// rows and clean "verified" matches waiting on a non-auto_publish source.
/// Nothing here writes to `events` except [EventDiscoveryRepository.approve]
/// — every other action is discovery-side only.
class EventDiscoveryPage extends ConsumerWidget {
  const EventDiscoveryPage({super.key});

  Future<void> _run(BuildContext context, WidgetRef ref, {required bool dryRun}) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(dryRun ? 'Running discovery (test mode)…' : 'Running discovery (live)…'),
      duration: const Duration(seconds: 30),
    ));
    try {
      final result =
          await ref.read(eventDiscoveryRepositoryProvider).runDiscovery(dryRun: dryRun);
      messenger.hideCurrentSnackBar();
      final results = (result['results'] as List?) ?? const [];
      final summary = results.map((r) {
        final m = (r as Map).cast<String, dynamic>();
        return '${m['sourceName']}: found ${m['discovered']}, new ${m['new']}, '
            'dup ${m['duplicates']}, review ${m['needsReview']}, rejected ${m['rejected']}'
            '${m['error'] != null ? ' — ${m['error']}' : ''}';
      }).join('\n');
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(dryRun ? 'Test run results' : 'Live run results'),
            content: SingleChildScrollView(child: Text(summary.isEmpty ? 'No sources ran.' : summary)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        );
      }
      ref.read(eventDiscoveryRefreshProvider.notifier).bump();
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Discovery run failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(eventSourcesProvider);
    final reviewAsync = ref.watch(discoveredEventsNeedingReviewProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Event Discovery',
          subtitle: 'Multiple sources -> Discovery -> Verification -> Deduplication -> '
              'Admin Approval -> Events. Ticketmaster is one source, not the whole system.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => _run(context, ref, dryRun: true),
              icon: const Icon(Icons.science_rounded, size: 18),
              label: const Text('Test run (no writes)'),
            ),
            const Gap.h(AppSpacing.sm),
            FilledButton.icon(
              onPressed: () => _run(context, ref, dryRun: false),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Run live'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.xl),
        Text('Sources', style: Theme.of(context).textTheme.titleMedium),
        const Gap.v(AppSpacing.md),
        sourcesAsync.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AdminEmptyState(message: 'Could not load sources: $e'),
          data: (sources) => sources.isEmpty
              ? const AdminEmptyState(
                  message: 'No sources configured. Run migration 0055.',
                  icon: Icons.travel_explore_rounded)
              : Column(children: [
                  for (final s in sources) ...[
                    _SourceCard(source: s),
                    const Gap.v(AppSpacing.sm),
                  ],
                ]),
        ),
        const Gap.v(AppSpacing.xl),
        Text('Awaiting Approval', style: Theme.of(context).textTheme.titleMedium),
        const Gap.v(AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final f in _ReviewFilter.values)
              ChoiceChip(
                label: Text(f.label),
                selected: ref.watch(_reviewFilterProvider) == f,
                onSelected: (_) => ref.read(_reviewFilterProvider.notifier).select(f),
              ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        reviewAsync.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AdminEmptyState(message: 'Could not load review queue: $e'),
          data: (allItems) {
            final filter = ref.watch(_reviewFilterProvider);
            final items = allItems.where(filter.matches).toList();
            if (allItems.isEmpty) {
              return const AdminEmptyState(
                  message: 'Nothing waiting on approval.', icon: Icons.inbox_rounded);
            }
            if (items.isEmpty) {
              return AdminEmptyState(
                  message: 'No ${filter.label.toLowerCase()} events waiting.',
                  icon: Icons.filter_alt_off_rounded);
            }
            return Column(children: [
              for (final item in items) ...[
                _ReviewCard(item: item),
                const Gap.v(AppSpacing.sm),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});
  final EventSourceRow source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasConnector = source.sourceType == 'api';
    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(source.name,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (!source.enabled)
            const StatusBadge(BadgeStatus.draft, label: 'Disabled')
          else if (source.autoPublish)
            const StatusBadge(BadgeStatus.published, label: 'Auto-publish')
          else
            const StatusBadge(BadgeStatus.review, label: 'Review required'),
        ]),
        if (source.sourceUrl != null) ...[
          const Gap.v(AppSpacing.xs),
          Text(source.sourceUrl!, style: theme.textTheme.bodySmall),
        ],
        if (!hasConnector && source.lastError != null) ...[
          const Gap.v(AppSpacing.sm),
          Text(source.lastError!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],
        if (hasConnector) ...[
          const Gap.v(AppSpacing.md),
          Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.xs, children: [
            _stat('Found', source.lastRunDiscovered),
            _stat('New', source.lastRunNew),
            _stat('Duplicates', source.lastRunDuplicates),
            _stat('Needs Review', source.lastRunNeedsReview),
            _stat('Rejected', source.lastRunRejected),
          ]),
          if (source.lastCheckedAt != null) ...[
            const Gap.v(AppSpacing.xs),
            Text('Last checked: ${source.lastCheckedAt}', style: theme.textTheme.bodySmall),
          ],
          if (source.lastError != null) ...[
            const Gap.v(AppSpacing.xs),
            Text('Last error: ${source.lastError}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
        ],
      ]),
    );
  }

  Widget _stat(String label, int value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.item});
  final DiscoveredEventRow item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final when = [
      if (item.startDate != null) item.startDate!.toIso8601String().split('T').first,
      if ((item.startTime ?? '').isNotEmpty) item.startTime,
    ].whereType<String>().join(' · ');
    final where = [
      if ((item.venueName ?? '').isNotEmpty) item.venueName,
      if ((item.city ?? '').isNotEmpty) item.city,
    ].whereType<String>().join(', ');

    return AdminSectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(item.name,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (item.matchConfidence != null)
            StatusBadge(BadgeStatus.review,
                label: 'Possible dup (${(item.matchConfidence! * 100).round()}%)'),
        ]),
        if (when.isNotEmpty || where.isNotEmpty) ...[
          const Gap.v(AppSpacing.xs),
          Text([when, where].where((s) => s.isNotEmpty).join(' · '),
              style: theme.textTheme.bodySmall),
        ],
        if ((item.category ?? '').isNotEmpty) ...[
          const Gap.v(AppSpacing.xs),
          Text('Category: ${item.category}', style: theme.textTheme.bodySmall),
        ],
        if (item.timeOfDay != null || item.experienceTags.isNotEmpty) ...[
          const Gap.v(AppSpacing.xs),
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [
            if (item.timeOfDay != null)
              StatusBadge(
                item.isEveningOrLater ? BadgeStatus.published : BadgeStatus.draft,
                label: item.timeOfDay!,
              ),
            for (final tag in item.experienceTags)
              StatusBadge(BadgeStatus.review, label: tag),
          ]),
        ],
        if (item.sourceUrl != null) ...[
          const Gap.v(AppSpacing.xs),
          InkWell(
            onTap: () {},
            child: Text('View original: ${item.sourceUrl}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(decoration: TextDecoration.underline)),
          ),
        ],
        const Gap.v(AppSpacing.md),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(eventDiscoveryRepositoryProvider).reject(item);
              ref.read(eventDiscoveryRefreshProvider.notifier).bump();
            },
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Reject'),
          ),
          const Gap.h(AppSpacing.sm),
          FilledButton.icon(
            onPressed: () async {
              await ref.read(eventDiscoveryRepositoryProvider).approve(item);
              ref.read(eventDiscoveryRefreshProvider.notifier).bump();
            },
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Approve & Publish'),
          ),
        ]),
      ]),
    );
  }
}
