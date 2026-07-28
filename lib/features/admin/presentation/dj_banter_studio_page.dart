import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/destinations/data/master_destination_repository.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/banter_category.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/dj_banter_clip.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/dj_banter_repository.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/gps_banter_director.dart';
import 'package:explorer_os_mobile/features/narration/voices.dart';

/// Admin → DJ Banter Studio.
///
/// Authoring + management surface for the GPS-aware, per-destination banter
/// library: generate, edit, preview, voice, assign destination/GPS region,
/// bulk-fill missing categories, search/filter, and review version history.
class DjBanterStudioPage extends StatelessWidget {
  const DjBanterStudioPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.dashboard_rounded), text: 'Dashboard'),
                Tab(icon: Icon(Icons.library_books_rounded), text: 'Library'),
                Tab(icon: Icon(Icons.auto_awesome_rounded), text: 'Generate'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [_DashboardTab(), _LibraryTab(), _GenerateTab()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared selected destination code across tabs.
final _selectedDestProvider =
    NotifierProvider<_SelDest, String?>(_SelDest.new);

class _SelDest extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

// ── Dashboard ────────────────────────────────────────────────────────────────

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final clips = ref.watch(djBanterAllProvider).value ?? const [];
    final dests = ref.watch(masterDestinationsProvider).value ?? const [];
    final selected = ref.watch(_selectedDestProvider);
    final coverage = computeCoverage(clips, destinationCode: selected);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'DJ Banter Studio',
          subtitle:
              'A live-host banter library for every destination. Target 20–50 '
              'unique clips per category; the Radio Director rotates them with '
              'cooldown + never-repeat-in-a-trip rules.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Row(
            children: [
              const Icon(Icons.travel_explore_rounded),
              const Gap.h(AppSpacing.md),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Destination',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All destinations')),
                    for (final d in dests)
                      if ((d.code ?? '').isNotEmpty)
                        DropdownMenuItem(
                            value: d.code, child: Text('${d.name} (${d.code})')),
                  ],
                  onChanged: (v) =>
                      ref.read(_selectedDestProvider.notifier).set(v),
                ),
              ),
            ],
          ),
        ),
        const Gap.v(AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AdminStatCard(
                label: 'Total clips',
                value: '${coverage.total}',
                icon: Icons.record_voice_over_rounded,
              ),
            ),
            const Gap.h(AppSpacing.md),
            Expanded(
              child: AdminStatCard(
                label: 'Categories covered',
                value: '${19 - coverage.missingCategories}/19',
                icon: Icons.category_rounded,
                tint: const Color(0xFF2E7D32),
              ),
            ),
            const Gap.h(AppSpacing.md),
            Expanded(
              child: AdminStatCard(
                label: 'Empty categories',
                value: '${coverage.missingCategories}',
                icon: Icons.report_gmailerrorred_rounded,
                tint: const Color(0xFFC0392B),
              ),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Coverage by category',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Gap.v(AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final c in BanterCategory.values)
                    _CoverageChip(
                        label: c.label,
                        count: coverage.byCategory[c] ?? 0,
                        target: kBanterTargetPerCategory),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoverageChip extends StatelessWidget {
  const _CoverageChip(
      {required this.label, required this.count, required this.target});
  final String label;
  final int count;
  final int target;

  @override
  Widget build(BuildContext context) {
    final ok = count >= target;
    final some = count > 0;
    final color = ok
        ? const Color(0xFF2E7D32)
        : some
            ? const Color(0xFF8A6D00)
            : const Color(0xFFC0392B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$label · $count',
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Library ──────────────────────────────────────────────────────────────────

class _LibraryTab extends ConsumerStatefulWidget {
  const _LibraryTab();
  @override
  ConsumerState<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<_LibraryTab> {
  final _search = TextEditingController();
  BanterCategory? _category;
  BanterStatus? _status;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DjBanterClip> _filter(List<DjBanterClip> all) {
    final q = _search.text.trim().toLowerCase();
    final dest = ref.read(_selectedDestProvider);
    return all.where((c) {
      if (dest != null && c.destinationCode != dest) return false;
      if (_category != null && c.category != _category) return false;
      if (_status != null && c.status != _status) return false;
      if (q.isEmpty) return true;
      return c.text.toLowerCase().contains(q) ||
          c.category.label.toLowerCase().contains(q) ||
          (c.destinationCode ?? '').toLowerCase().contains(q) ||
          (c.gpsRegion ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(djBanterAllProvider);
    final clips = _filter(async.value ?? const []);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Banter Library',
          subtitle: 'Search, filter, edit, preview, voice, and manage clips.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            children: [
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search banter',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const Gap.v(AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<BanterCategory?>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Category',
                          isDense: true,
                          border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All')),
                        for (final c in BanterCategory.values)
                          DropdownMenuItem(value: c, child: Text(c.label)),
                      ],
                      onChanged: (c) => setState(() => _category = c),
                    ),
                  ),
                  const Gap.h(AppSpacing.md),
                  Expanded(
                    child: DropdownButtonFormField<BanterStatus?>(
                      initialValue: _status,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Status',
                          isDense: true,
                          border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All')),
                        for (final s in BanterStatus.values)
                          DropdownMenuItem(value: s, child: Text(s.name)),
                      ],
                      onChanged: (s) => setState(() => _status = s),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Gap.v(AppSpacing.md),
        if (async.isLoading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (clips.isEmpty)
          const AdminEmptyState(
            message: 'No banter yet. Generate some in the Generate tab.',
            icon: Icons.record_voice_over_rounded,
          )
        else ...[
          Text('${clips.length} clip(s)', style: theme.textTheme.bodySmall),
          const Gap.v(AppSpacing.sm),
          for (final c in clips) ...[
            _BanterCard(clip: c),
            const Gap.v(AppSpacing.sm),
          ],
        ],
      ],
    );
  }
}

class _BanterCard extends ConsumerWidget {
  const _BanterCard({required this.clip});
  final DjBanterClip clip;

  BadgeStatus get _badge => switch (clip.status) {
        BanterStatus.published => BadgeStatus.published,
        BanterStatus.approved => BadgeStatus.review,
        BanterStatus.archived => BadgeStatus.planned,
        BanterStatus.draft => BadgeStatus.draft,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(djBanterRepositoryProvider);
    void refresh() => ref.read(djBanterRefreshProvider.notifier).bump();

    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(clip.category.label,
                    style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              const Gap.h(AppSpacing.sm),
              StatusBadge(_badge, label: clip.status.name),
              const Spacer(),
              if (clip.hasAudio)
                const Icon(Icons.volume_up_rounded, size: 18),
              _menu(context, ref, repo, refresh),
            ],
          ),
          const Gap.v(AppSpacing.sm),
          Text('"${clip.text}"',
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
          const Gap.v(AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              if ((clip.destinationCode ?? '').isNotEmpty)
                _meta(Icons.place_rounded, clip.destinationCode!),
              if ((clip.gpsRegion ?? '').isNotEmpty)
                _meta(Icons.my_location_rounded, clip.gpsRegion!),
              if ((clip.voiceName ?? '').isNotEmpty)
                _meta(Icons.graphic_eq_rounded, clip.voiceName!),
              _meta(Icons.play_arrow_rounded, 'plays ${clip.playCount}'),
              _meta(Icons.history_rounded, 'v${clip.version}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      );

  Widget _menu(BuildContext context, WidgetRef ref, DjBanterRepository repo,
      VoidCallback refresh) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            await _editDialog(context, repo, refresh);
          case 'preview':
            await _previewDialog(context);
          case 'voice':
            await _voiceDialog(context, repo, refresh);
          case 'destination':
            await _destinationDialog(context, ref, repo, refresh);
          case 'region':
            await _regionDialog(context, repo, refresh);
          case 'audio':
            await repo.enqueueVoiceJob(
                destinationCode: clip.destinationCode ?? '');
            if (context.mounted) {
              _toast(context, 'Queued audio generation');
            }
          case 'approve':
            await repo.setStatus(clip.id, BanterStatus.approved);
            refresh();
          case 'publish':
            await repo.setStatus(clip.id, BanterStatus.published);
            refresh();
          case 'archive':
            await repo.setStatus(clip.id, BanterStatus.archived);
            refresh();
          case 'history':
            await _historyDialog(context, repo);
          case 'delete':
            await repo.delete(clip.id);
            refresh();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit banter')),
        PopupMenuItem(value: 'preview', child: Text('Preview')),
        PopupMenuItem(value: 'voice', child: Text('Assign voice')),
        PopupMenuItem(value: 'destination', child: Text('Assign destination')),
        PopupMenuItem(value: 'region', child: Text('Assign GPS region')),
        PopupMenuItem(value: 'audio', child: Text('Generate audio')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'approve', child: Text('Approve')),
        PopupMenuItem(value: 'publish', child: Text('Publish')),
        PopupMenuItem(value: 'archive', child: Text('Archive')),
        PopupMenuItem(value: 'history', child: Text('Version history')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  Future<void> _editDialog(
      BuildContext context, DjBanterRepository repo, VoidCallback refresh) async {
    final controller = TextEditingController(text: clip.text);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit banter'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              helperText: 'Use {placeholders} like {upcoming_attraction}, '
                  '{county}, {road}, {nearby_wildlife}.',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await repo.saveEdit(clip, controller.text.trim());
      refresh();
    }
  }

  Future<void> _previewDialog(BuildContext context) async {
    final ctx = GpsBanterContext(
      park: clip.gpsRegion ?? clip.destinationCode ?? 'Ocala National Forest',
      county: 'Marion County',
      upcomingAttraction: 'Juniper Springs',
      road: 'FL-40',
      nearbyWildlife: const ['Florida black bears'],
      nearbySprings: const ['Silver Glen Springs'],
      nearbyTrails: const ['Yearling Trail'],
      destinationCode: clip.destinationCode,
    );
    final filled = fillBanter(clip.text, ctx);
    await showDialog<void>(
      context: context,
      builder: (_) => _PreviewDialog(clip: clip, filledText: filled),
    );
  }

  Future<void> _voiceDialog(
      BuildContext context, DjBanterRepository repo, VoidCallback refresh) async {
    var voiceId = clip.voiceId ?? narrationVoices.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Assign voice'),
        content: StatefulBuilder(
          builder: (_, setSB) => DropdownButtonFormField<String>(
            initialValue: voiceId,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final v in narrationVoices)
                DropdownMenuItem(value: v.id, child: Text(v.name)),
            ],
            onChanged: (v) => setSB(() => voiceId = v ?? voiceId),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Assign')),
        ],
      ),
    );
    if (ok == true) {
      await repo.setVoice(clip.id, voiceId, voiceNameForId(voiceId) ?? voiceId);
      refresh();
    }
  }

  Future<void> _destinationDialog(BuildContext context, WidgetRef ref,
      DjBanterRepository repo, VoidCallback refresh) async {
    final dests = ref.read(masterDestinationsProvider).value ?? const [];
    var code = clip.destinationCode;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Assign destination'),
        content: StatefulBuilder(
          builder: (_, setSB) => DropdownButtonFormField<String?>(
            initialValue: code,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('(none)')),
              for (final d in dests)
                if ((d.code ?? '').isNotEmpty)
                  DropdownMenuItem(
                      value: d.code, child: Text('${d.name} (${d.code})')),
            ],
            onChanged: (v) => setSB(() => code = v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Assign')),
        ],
      ),
    );
    if (ok == true) {
      await repo.assignDestination(clip.id, code);
      refresh();
    }
  }

  Future<void> _regionDialog(
      BuildContext context, DjBanterRepository repo, VoidCallback refresh) async {
    final controller = TextEditingController(text: clip.gpsRegion ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Assign GPS region'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Region / park name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Assign')),
        ],
      ),
    );
    if (ok == true) {
      final v = controller.text.trim();
      await repo.assignRegion(clip.id, v.isEmpty ? null : v);
      refresh();
    }
  }

  Future<void> _historyDialog(
      BuildContext context, DjBanterRepository repo) async {
    final versions = await repo.versions(clip.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Version history'),
        content: SizedBox(
          width: 520,
          child: versions.isEmpty
              ? const Text('No prior versions yet.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final v in versions) ...[
                      Text('v${v.version}'
                          '${v.author != null ? ' · ${v.author}' : ''}',
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('"${v.text ?? ''}"'),
                      const Divider(),
                    ],
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.clip, required this.filledText});
  final DjBanterClip clip;
  final String filledText;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  AudioPlayer? _player;
  bool _playing = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final url = widget.clip.audioUrl;
    if (url == null || url.isEmpty) return;
    _player ??= AudioPlayer();
    try {
      await _player!.setUrl(url);
      setState(() => _playing = true);
      await _player!.play();
      if (mounted) setState(() => _playing = false);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Preview · ${widget.clip.category.label}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${widget.filledText}"',
                style: const TextStyle(fontStyle: FontStyle.italic, height: 1.4)),
            const SizedBox(height: 12),
            Text('Transitions into: ${widget.clip.category.transition.name}',
                style: const TextStyle(fontSize: 12)),
            if (widget.clip.hasAudio) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _playing ? null : _play,
                icon: Icon(_playing
                    ? Icons.hourglass_top_rounded
                    : Icons.play_arrow_rounded),
                label: Text(_playing ? 'Playing…' : 'Play audio'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}

// ── Generate ─────────────────────────────────────────────────────────────────

class _GenerateTab extends ConsumerStatefulWidget {
  const _GenerateTab();
  @override
  ConsumerState<_GenerateTab> createState() => _GenerateTabState();
}

class _GenerateTabState extends ConsumerState<_GenerateTab> {
  BanterCategory _category = BanterCategory.welcome;
  int _count = 20;
  final _region = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _region.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dests = ref.watch(masterDestinationsProvider).value ?? const [];
    final selected = ref.watch(_selectedDestProvider);
    final repo = ref.read(djBanterRepositoryProvider);
    void refresh() => ref.read(djBanterRefreshProvider.notifier).bump();

    Future<void> run(Future<int> Function() action, String verb) async {
      setState(() => _busy = true);
      try {
        final n = await action();
        refresh();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$verb $n banter clip(s)')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Failed: $e')));
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Generate Banter',
          subtitle:
              'Instantly generate GPS-aware clips from the seed library. For '
              'larger, richer batches, run tool/dj_banter_generate.dart (OpenAI).',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Destination',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('(unassigned)')),
                  for (final d in dests)
                    if ((d.code ?? '').isNotEmpty)
                      DropdownMenuItem(
                          value: d.code, child: Text('${d.name} (${d.code})')),
                ],
                onChanged: (v) =>
                    ref.read(_selectedDestProvider.notifier).set(v),
              ),
              const Gap.v(AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<BanterCategory>(
                      initialValue: _category,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Category',
                          isDense: true,
                          border: OutlineInputBorder()),
                      items: [
                        for (final c in BanterCategory.values)
                          DropdownMenuItem(value: c, child: Text(c.label)),
                      ],
                      onChanged: (c) => setState(() => _category = c ?? _category),
                    ),
                  ),
                  const Gap.h(AppSpacing.md),
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<int>(
                      initialValue: _count,
                      decoration: const InputDecoration(
                          labelText: 'Count',
                          isDense: true,
                          border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 10, child: Text('10')),
                        DropdownMenuItem(value: 20, child: Text('20')),
                        DropdownMenuItem(value: 30, child: Text('30')),
                        DropdownMenuItem(value: 40, child: Text('40')),
                      ],
                      onChanged: (v) => setState(() => _count = v ?? _count),
                    ),
                  ),
                ],
              ),
              const Gap.v(AppSpacing.md),
              TextField(
                controller: _region,
                decoration: const InputDecoration(
                    labelText: 'GPS region (optional)',
                    isDense: true,
                    border: OutlineInputBorder()),
              ),
              const Gap.v(AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => run(
                              () => repo.generate(
                                _category,
                                count: _count,
                                destinationCode: selected,
                                gpsRegion: _region.text.trim().isEmpty
                                    ? null
                                    : _region.text.trim(),
                              ),
                              'Generated',
                            ),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text('Generate ${_category.label}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: (_busy || selected == null)
                        ? null
                        : () => run(
                              () => repo.generateMissing(
                                destinationCode: selected,
                                gpsRegion: _region.text.trim().isEmpty
                                    ? null
                                    : _region.text.trim(),
                              ),
                              'Generated',
                            ),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: const Text('Bulk generate missing'),
                  ),
                  if (selected != null)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              await repo.enqueueVoiceJob(
                                  destinationCode: selected);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Queued audio generation')));
                              }
                            },
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44)),
                      icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                      label: const Text('Generate audio (queue)'),
                    ),
                ],
              ),
              if (selected == null) ...[
                const Gap.v(AppSpacing.sm),
                Text(
                    'Pick a destination to bulk-fill or voice its library. '
                    'Single-category generation works unassigned too.',
                    style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
