import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/destinations/data/master_destination_repository.dart';
import 'package:explorer_os_mobile/features/destinations/models/master_destination.dart';

/// The Master Destination dashboard: the source of truth for every destination.
/// Lists destinations with AI-status indicators + counts, supports filtering,
/// and launches AI jobs per destination.
class DestinationDashboardPage extends ConsumerStatefulWidget {
  const DestinationDashboardPage({super.key});

  @override
  ConsumerState<DestinationDashboardPage> createState() =>
      _DestinationDashboardPageState();
}

class _DestinationDashboardPageState
    extends ConsumerState<DestinationDashboardPage> {
  final _search = TextEditingController();
  String _type = 'All';
  String _county = 'All';
  String _region = 'All';
  String _published = 'All';
  String _research = 'All';
  String _audio = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Iterable<MasterDestination> _filter(List<MasterDestination> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((d) {
      if (q.isNotEmpty &&
          !d.name.toLowerCase().contains(q) &&
          !(d.code ?? '').toLowerCase().contains(q)) {
        return false;
      }
      if (_type != 'All' && (d.type ?? '') != _type) return false;
      if (_county != 'All' && (d.county ?? '') != _county) return false;
      if (_region != 'All' && (d.region ?? '') != _region) return false;
      if (_published == 'Published' && !d.published) return false;
      if (_published == 'Unpublished' && d.published) return false;
      if (_research != 'All' && d.researchStatus.label != _research) {
        return false;
      }
      if (_audio != 'All' && d.audioStatus.label != _audio) return false;
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(masterDestinationsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AdminEmptyState(
          icon: Icons.error_outline_rounded, message: 'Could not load: $e'),
      data: (all) {
        final types = _distinct(all.map((d) => d.type));
        final counties = _distinct(all.map((d) => d.county));
        final regions = _distinct(all.map((d) => d.region));
        final shown = _filter(all).toList(growable: false);
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            AdminPageHeader(
              title: 'Destinations',
              subtitle:
                  'Master destination system — every park, forest, spring, city, '
                  'and business, with AI content status.',
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () =>
                      ref.read(destinationsRefreshProvider.notifier).bump(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const Gap.v(AppSpacing.lg),
            _StatCards(all: all),
            const Gap.v(AppSpacing.lg),
            AdminSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Search by name or code…',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                      ),
                    ),
                  ),
                  const Gap.v(AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _FilterDropdown(
                          label: 'Type',
                          value: _type,
                          options: ['All', ...types],
                          onChanged: (v) => setState(() => _type = v)),
                      _FilterDropdown(
                          label: 'County',
                          value: _county,
                          options: ['All', ...counties],
                          onChanged: (v) => setState(() => _county = v)),
                      _FilterDropdown(
                          label: 'Region',
                          value: _region,
                          options: ['All', ...regions],
                          onChanged: (v) => setState(() => _region = v)),
                      _FilterDropdown(
                          label: 'Published',
                          value: _published,
                          options: const ['All', 'Published', 'Unpublished'],
                          onChanged: (v) => setState(() => _published = v)),
                      _FilterDropdown(
                          label: 'Research',
                          value: _research,
                          options: const [
                            'All',
                            'Pending',
                            'In progress',
                            'Complete'
                          ],
                          onChanged: (v) => setState(() => _research = v)),
                      _FilterDropdown(
                          label: 'Audio',
                          value: _audio,
                          options: const [
                            'All',
                            'Pending',
                            'In progress',
                            'Complete'
                          ],
                          onChanged: (v) => setState(() => _audio = v)),
                    ],
                  ),
                ],
              ),
            ),
            const Gap.v(AppSpacing.md),
            Text('${shown.length} of ${all.length} destinations',
                style: Theme.of(context).textTheme.bodySmall),
            const Gap.v(AppSpacing.sm),
            if (shown.isEmpty)
              const AdminEmptyState(message: 'No destinations match the filters.')
            else
              for (final d in shown) ...[
                _DestinationCard(destination: d),
                const Gap.v(AppSpacing.md),
              ],
          ],
        );
      },
    );
  }

  static List<String> _distinct(Iterable<String?> values) {
    final set = <String>{
      for (final v in values)
        if (v != null && v.trim().isNotEmpty) v
    };
    final list = set.toList()..sort();
    return list;
  }
}

class _StatCards extends StatelessWidget {
  const _StatCards({required this.all});
  final List<MasterDestination> all;

  @override
  Widget build(BuildContext context) {
    final published = all.where((d) => d.published).length;
    final gps = all.where((d) => d.gpsReady).length;
    final missingAudio = all.where((d) => d.audioCount == 0).length;
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 2 : 1);
      final width = (c.maxWidth - (cols - 1) * AppSpacing.md) / cols;
      return Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          SizedBox(
              width: width,
              child: AdminStatCard(
                  label: 'Total destinations',
                  value: '${all.length}',
                  icon: Icons.public_rounded)),
          SizedBox(
              width: width,
              child: AdminStatCard(
                  label: 'Published',
                  value: '$published',
                  icon: Icons.verified_rounded,
                  tint: const Color(0xFF2E7D32))),
          SizedBox(
              width: width,
              child: AdminStatCard(
                  label: 'GPS ready',
                  value: '$gps',
                  icon: Icons.my_location_rounded,
                  tint: const Color(0xFF2C6E8F))),
          SizedBox(
              width: width,
              child: AdminStatCard(
                  label: 'Missing audio',
                  value: '$missingAudio',
                  icon: Icons.music_off_rounded,
                  tint: const Color(0xFFC0392B))),
        ],
      );
    });
  }
}

class _DestinationCard extends ConsumerWidget {
  const _DestinationCard({required this.destination});
  final MasterDestination destination;

  Future<void> _launch(
      BuildContext context, WidgetRef ref, DestinationAiJob job) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(masterDestinationRepositoryProvider)
          .launchJob(destination, job);
      ref.read(destinationsRefreshProvider.notifier).bump();
      messenger.showSnackBar(SnackBar(
          content: Text('${job.label} queued for ${destination.name}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _togglePublish(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(masterDestinationRepositoryProvider)
          .setPublished(destination.id, !destination.published);
      ref.read(destinationsRefreshProvider.notifier).bump();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final d = destination;
    final meta = [
      if (d.type != null) d.type!,
      if (d.county != null) '${d.county} County',
      if (d.region != null) d.region!,
      if (d.state != null) d.state!,
    ].join('  ·  ');
    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(d.name,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        if (d.code != null) ...[
                          const Gap.h(AppSpacing.sm),
                          _CodeChip(d.code!),
                        ],
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const Gap.v(AppSpacing.xs),
                      Text(meta, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              _ActionsMenu(
                onJob: (job) => _launch(context, ref, job),
                onTogglePublish: () => _togglePublish(context, ref),
                published: d.published,
              ),
            ],
          ),
          const Gap.v(AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _StatusChip('Research', d.researchStatus),
              _StatusChip('Story', d.storyStatus),
              _StatusChip('Audio', d.audioStatus),
              _StatusChip('Image', d.imageStatus),
              _BoolChip('GPS', d.gpsReady),
              _BoolChip('Published', d.published),
            ],
          ),
          const Gap.v(AppSpacing.md),
          Text(
            'Stories ${d.storyCount}   ·   Audio ${d.audioCount}   ·   '
            'Images ${d.imageCount}   ·   Plays ${d.playCount}'
            '${d.updatedAt != null ? '   ·   Updated ${_fmt(d.updatedAt!)}' : ''}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.disabledColor),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({
    required this.onJob,
    required this.onTogglePublish,
    required this.published,
  });
  final void Function(DestinationAiJob) onJob;
  final VoidCallback onTogglePublish;
  final bool published;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) {
        if (v == 'publish') {
          onTogglePublish();
        } else {
          onJob(DestinationAiJob.values.firstWhere((j) => j.name == v));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'publish',
          child: Row(children: [
            Icon(published
                ? Icons.unpublished_rounded
                : Icons.publish_rounded),
            const SizedBox(width: 10),
            Text(published ? 'Unpublish' : 'Publish'),
          ]),
        ),
        const PopupMenuDivider(),
        for (final job in DestinationAiJob.values)
          PopupMenuItem(
            value: job.name,
            child: Row(children: [
              const Icon(Icons.auto_awesome_rounded, size: 18),
              const SizedBox(width: 10),
              Text(job.label),
            ]),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.label, this.status);
  final String label;
  final DestinationStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      DestinationStatus.complete => (
          const Color(0xFF2E7D32),
          Icons.check_circle_rounded
        ),
      DestinationStatus.inProgress => (
          const Color(0xFF8A6D00),
          Icons.timelapse_rounded
        ),
      DestinationStatus.pending => (
          const Color(0xFF9AA0A6),
          Icons.radio_button_unchecked_rounded
        ),
    };
    return _Pill(color: color, icon: icon, text: '$label: ${status.label}');
  }
}

class _BoolChip extends StatelessWidget {
  const _BoolChip(this.label, this.on);
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final color = on ? const Color(0xFF2C6E8F) : const Color(0xFF9AA0A6);
    return _Pill(
      color: color,
      icon: on ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
      text: on ? '$label ✓' : label,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip(this.code);
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: AppRadius.smAll,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Text(code,
          style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace', fontWeight: FontWeight.w700)),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final safe = options.contains(value) ? value : options.first;
    return SizedBox(
      width: 190,
      child: DropdownButtonFormField<String>(
        initialValue: safe,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final o in options)
            DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => onChanged(v ?? 'All'),
      ),
    );
  }
}
