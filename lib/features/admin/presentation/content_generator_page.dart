import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/content_generator/data/content_generator_repository.dart';
import 'package:explorer_os_mobile/features/content_generator/models/content_models.dart';
import 'package:explorer_os_mobile/features/story_studio/data/story_library_repository.dart';

/// Admin → Content Generator: the master content engine. Enter a destination,
/// queue background research/story/audio jobs, review the knowledge base and
/// stories, and publish for GPS-triggered playback. Heavy lifting (LLM research,
/// ElevenLabs audio) runs server-side via the tools that process the job queue.
class ContentGeneratorPage extends StatelessWidget {
  const ContentGeneratorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.add_location_alt_rounded), text: 'Destinations'),
                Tab(icon: Icon(Icons.psychology_rounded), text: 'Knowledge Base'),
                Tab(icon: Icon(Icons.work_history_rounded), text: 'Generation Jobs'),
                Tab(icon: Icon(Icons.rule_rounded), text: 'Review Queue'),
                Tab(icon: Icon(Icons.public_rounded), text: 'Published'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                _DestinationsTab(),
                _KnowledgeTab(),
                _JobsTab(),
                _ReviewTab(),
                _PublishedTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Destinations (builder) ────────────────────────────────────────────────────

class _DestinationsTab extends ConsumerStatefulWidget {
  const _DestinationsTab();
  @override
  ConsumerState<_DestinationsTab> createState() => _DestinationsTabState();
}

class _DestinationsTabState extends ConsumerState<_DestinationsTab> {
  final _name = TextEditingController();
  final _state = TextEditingController(text: 'Florida');
  final _county = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _radius = TextEditingController(text: '150');
  final _website = TextEditingController();
  final _notes = TextEditingController();
  DestinationCategory _category = DestinationCategory.nationalForest;
  bool _saving = false;
  String? _message;

  @override
  void dispose() {
    for (final c in [_name, _state, _county, _lat, _lng, _radius, _website, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _enqueue(JobType type) async {
    if (_name.text.trim().isEmpty) {
      setState(() => _message = 'Destination name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await ref.read(contentGeneratorRepositoryProvider).enqueue(GenerationJob(
            id: '',
            destination: _name.text.trim(),
            jobType: type,
            status: JobStatus.pending,
            destinationCategory: _category.dbValue,
            state: _state.text.trim().isEmpty ? null : _state.text.trim(),
            county: _county.text.trim().isEmpty ? null : _county.text.trim(),
            latitude: double.tryParse(_lat.text.trim()),
            longitude: double.tryParse(_lng.text.trim()),
            radiusM: int.tryParse(_radius.text.trim()) ?? 150,
            website: _website.text.trim().isEmpty ? null : _website.text.trim(),
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          ));
      ref.read(contentRefreshProvider.notifier).bump();
      setState(() {
        _saving = false;
        _message = 'Queued a ${type.label} job for "${_name.text.trim()}". '
            'Run the research/generate tools to process the queue.';
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _message = 'Queue failed (signed in? migration 0018 run?): $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Destination Builder',
          subtitle: 'Enter a destination and queue background jobs to research, '
              'write, voice, and publish its content.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _f(_name, 'Destination name *')),
              const Gap.h(AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<DestinationCategory>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Category', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final c in DestinationCategory.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (c) => setState(() => _category = c ?? _category),
                ),
              ),
            ]),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(child: _f(_state, 'State')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_county, 'County')),
            ]),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(child: _f(_lat, 'Latitude')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_lng, 'Longitude')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_radius, 'Radius (m)')),
            ]),
            const Gap.v(AppSpacing.sm),
            _f(_website, 'Website (optional)'),
            const Gap.v(AppSpacing.sm),
            _f(_notes, 'Notes', lines: 2),
            const Gap.v(AppSpacing.md),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
              FilledButton.icon(
                onPressed: _saving ? null : () => _enqueue(JobType.research),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Research Destination'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _enqueue(JobType.stories),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: const Text('Generate Stories'),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _enqueue(JobType.full),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Full Pipeline'),
              ),
            ]),
            if (_message != null) ...[
              const Gap.v(AppSpacing.sm),
              Text(_message!, style: theme.textTheme.bodySmall),
            ],
          ]),
        ),
      ],
    );
  }

  Widget _f(TextEditingController c, String label, {int lines = 1}) => TextField(
      controller: c,
      maxLines: lines,
      decoration: InputDecoration(
          labelText: label, isDense: true, border: const OutlineInputBorder()));
}

// ── Knowledge Base ──────────────────────────────────────────────────────────

class _KnowledgeTab extends ConsumerStatefulWidget {
  const _KnowledgeTab();
  @override
  ConsumerState<_KnowledgeTab> createState() => _KnowledgeTabState();
}

class _KnowledgeTabState extends ConsumerState<_KnowledgeTab> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(knowledgeBaseProvider);
    final repo = ref.read(contentGeneratorRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Knowledge Base',
          subtitle: 'Researched facts, organized by destination and category.',
        ),
        const Gap.v(AppSpacing.lg),
        TextField(
          onChanged: (v) => setState(() => _q = v.toLowerCase()),
          decoration: const InputDecoration(
              labelText: 'Search facts',
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder()),
        ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Could not load knowledge base.\n$e')),
          data: (facts) {
            final rows = facts.where((f) {
              if (_q.isEmpty) return true;
              return f.title.toLowerCase().contains(_q) ||
                  f.destination.toLowerCase().contains(_q) ||
                  f.category.toLowerCase().contains(_q);
            }).toList();
            if (rows.isEmpty) {
              return const AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.psychology_rounded,
                      message: 'No facts yet. Queue a Research job, then run '
                          'tool/research_destination.dart.'));
            }
            return AdminSectionCard(
              child: Column(children: [
                for (final f in rows) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(f.title,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      f.destination,
                      f.category,
                      'conf ${(f.confidenceScore * 100).round()}%',
                    ].join('  ·  ')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      StatusBadge(f.approved
                          ? BadgeStatus.published
                          : BadgeStatus.review),
                      if (!f.approved)
                        IconButton(
                          tooltip: 'Approve',
                          icon: const Icon(Icons.check_rounded),
                          onPressed: () async {
                            await repo.approveFact(f.id);
                            ref.read(contentRefreshProvider.notifier).bump();
                          },
                        ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          await repo.deleteFact(f.id);
                          ref.read(contentRefreshProvider.notifier).bump();
                        },
                      ),
                    ]),
                  ),
                  const Divider(height: 1),
                ],
              ]),
            );
          },
        ),
      ],
    );
  }
}

// ── Generation Jobs ─────────────────────────────────────────────────────────

class _JobsTab extends ConsumerWidget {
  const _JobsTab();

  static Color _statusColor(JobStatus s) {
    switch (s) {
      case JobStatus.completed:
        return const Color(0xFF2E7D32);
      case JobStatus.failed:
        return const Color(0xFFC0392B);
      case JobStatus.waitingForReview:
        return const Color(0xFF8A6D00);
      case JobStatus.pending:
        return const Color(0xFF6A5ACD);
      default:
        return const Color(0xFF2C6E8F);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(generationJobsProvider);
    final repo = ref.read(contentGeneratorRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Generation Jobs',
          subtitle: 'Background jobs process one destination at a time: research '
              '→ knowledge → stories → audio → review → publish.',
        ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Could not load jobs.\n$e')),
          data: (jobs) => jobs.isEmpty
              ? const AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.work_history_rounded,
                      message: 'No jobs yet. Queue one from the Destinations tab.'))
              : AdminSectionCard(
                  child: Column(children: [
                    for (final j in jobs) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(j.destination,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          j.jobType.label,
                          if (j.progress > 0) '${j.progress}%',
                          if (j.message != null) j.message!,
                        ].join('  ·  '),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor(j.status).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(j.status.label,
                                style: TextStyle(
                                    color: _statusColor(j.status),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (j.status == JobStatus.failed)
                            IconButton(
                              tooltip: 'Retry',
                              icon: const Icon(Icons.refresh_rounded),
                              onPressed: () async {
                                await repo.retry(j.id);
                                ref.read(contentRefreshProvider.notifier).bump();
                              },
                            ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              await repo.deleteJob(j.id);
                              ref.read(contentRefreshProvider.notifier).bump();
                            },
                          ),
                        ]),
                      ),
                      const Divider(height: 1),
                    ],
                  ]),
                ),
        ),
      ],
    );
  }
}

// ── Review Queue (knowledge facts awaiting approval) ──────────────────────────

class _ReviewTab extends ConsumerWidget {
  const _ReviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(knowledgeBaseProvider);
    final repo = ref.read(contentGeneratorRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Review Queue',
          subtitle: 'Verify researched facts before they feed the story '
              'generator. (Story/audio review lives in Story Studio.)',
        ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (facts) {
            final pending = facts.where((f) => !f.approved).toList();
            if (pending.isEmpty) {
              return const AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.check_circle_rounded,
                      message: 'Nothing to review.'));
            }
            return Column(children: [
              for (final f in pending) ...[
                AdminSectionCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${f.title}  ·  ${f.category}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(f.destination, style: theme.textTheme.bodySmall),
                    if (f.description != null) ...[
                      const Gap.v(AppSpacing.xs),
                      Text(f.description!, style: theme.textTheme.bodyMedium),
                    ],
                    const Gap.v(AppSpacing.md),
                    Row(children: [
                      FilledButton.icon(
                        onPressed: () async {
                          await repo.approveFact(f.id);
                          ref.read(contentRefreshProvider.notifier).bump();
                        },
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Approve fact'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await repo.deleteFact(f.id);
                          ref.read(contentRefreshProvider.notifier).bump();
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Discard'),
                      ),
                    ]),
                  ]),
                ),
                const Gap.v(AppSpacing.md),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

// ── Published Library (published stories) ─────────────────────────────────────

class _PublishedTab extends ConsumerWidget {
  const _PublishedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(storyLibraryProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Published Library',
          subtitle: 'Live, GPS-triggered stories produced by the pipeline.',
        ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (stories) {
            final live = stories.where((s) => s.published).toList();
            if (live.isEmpty) {
              return const AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.public_rounded,
                      message: 'No published stories yet.'));
            }
            return AdminSectionCard(
              child: Column(children: [
                for (final s in live) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.graphic_eq_rounded, color: Colors.teal),
                    title: Text(s.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      s.category.label,
                      if (s.location != null) s.location!,
                      'plays: ${s.playCount}',
                    ].join('  ·  ')),
                    trailing: const StatusBadge(BadgeStatus.published),
                  ),
                  const Divider(height: 1),
                ],
              ]),
            );
          },
        ),
      ],
    );
  }
}
