import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/narration/data/voice_repository.dart';
import 'package:explorer_os_mobile/features/story_studio/data/story_library_repository.dart';
import 'package:explorer_os_mobile/features/story_studio/models/story_category.dart';
import 'package:explorer_os_mobile/features/story_studio/models/story_entry.dart';
import 'package:explorer_os_mobile/features/story_studio/services/story_composer.dart';

/// Admin → Story Studio: the AI story-production pipeline. Generate varied
/// story drafts, review/approve them, define GPS zones, group into collections,
/// and (via tool/story_audio.dart) voice + publish for GPS-triggered playback.
class StoryStudioPage extends StatelessWidget {
  const StoryStudioPage({super.key});

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
                Tab(icon: Icon(Icons.menu_book_rounded), text: 'Story Library'),
                Tab(icon: Icon(Icons.auto_awesome_rounded), text: 'AI Generator'),
                Tab(icon: Icon(Icons.rule_rounded), text: 'Approval Queue'),
                Tab(icon: Icon(Icons.place_rounded), text: 'GPS Zones'),
                Tab(icon: Icon(Icons.collections_bookmark_rounded), text: 'Collections'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                _LibraryTab(),
                _GeneratorTab(),
                _ApprovalTab(),
                _GpsZonesTab(),
                _CollectionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Story Library ─────────────────────────────────────────────────────────────

class _LibraryTab extends ConsumerStatefulWidget {
  const _LibraryTab();
  @override
  ConsumerState<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<_LibraryTab> {
  StoryCategory? _category;
  bool _publishedOnly = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(storyLibraryProvider);
    final repo = ref.read(storyLibraryRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Story Library',
          subtitle: 'Every generated story — filter, preview, approve, publish.',
        ),
        const Gap.v(AppSpacing.lg),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<StoryCategory?>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Category', isDense: true, border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('All categories')),
                for (final c in StoryCategory.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
          ),
          FilterChip(
            label: const Text('Published only'),
            selected: _publishedOnly,
            onSelected: (v) => setState(() => _publishedOnly = v),
          ),
        ]),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Could not load stories.\n$e')),
          data: (all) {
            final rows = all.where((s) {
              if (_category != null && s.category != _category) return false;
              if (_publishedOnly && !s.published) return false;
              return true;
            }).toList();
            if (rows.isEmpty) {
              return const AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.menu_book_rounded,
                      message: 'No stories yet. Generate some in "AI Generator".'));
            }
            return AdminSectionCard(
              child: Column(children: [
                for (final s in rows) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        s.hasAudio
                            ? Icons.graphic_eq_rounded
                            : Icons.article_rounded,
                        color: s.hasAudio ? Colors.teal : theme.disabledColor),
                    title: Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      s.category.label,
                      if (s.variation != null) s.variation!,
                      if (s.location != null) s.location!,
                      s.status.label,
                      'plays: ${s.playCount}',
                    ].join('  ·  '),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      StatusBadge(s.published
                          ? BadgeStatus.published
                          : (s.approved ? BadgeStatus.review : BadgeStatus.draft)),
                      IconButton(
                        tooltip: 'Preview',
                        icon: const Icon(Icons.visibility_rounded),
                        onPressed: () => _preview(context, s),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'approve') {
                            await repo.approve(s.id);
                          } else if (v == 'publish') {
                            await repo.publish(s.id, !s.published);
                          } else if (v == 'delete') {
                            await repo.delete(s.id);
                          }
                          ref.read(storyRefreshProvider.notifier).bump();
                        },
                        itemBuilder: (_) => [
                          if (!s.approved)
                            const PopupMenuItem(
                                value: 'approve', child: Text('Approve')),
                          PopupMenuItem(
                              value: 'publish',
                              enabled: s.hasAudio,
                              child: Text(s.published
                                  ? 'Unpublish'
                                  : (s.hasAudio ? 'Publish' : 'Publish (needs audio)'))),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
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

  void _preview(BuildContext context, StoryEntry s) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (s.transcript != null) Text(s.transcript!),
              const Gap.v(AppSpacing.md),
              if (s.hasAudio) _StoryPlayer(url: s.audioUrl!),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _StoryPlayer extends StatefulWidget {
  const _StoryPlayer({required this.url});
  final String url;
  @override
  State<_StoryPlayer> createState() => _StoryPlayerState();
}

class _StoryPlayerState extends State<_StoryPlayer> {
  final _player = AudioPlayer();
  String? _error;
  @override
  void initState() {
    super.initState();
    _player.setUrl(widget.url).catchError((e) {
      if (mounted) setState(() => _error = '$e');
      return null;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Text('Could not load audio.\n$_error');
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        return IconButton.filled(
          iconSize: 30,
          onPressed: () => playing ? _player.pause() : _player.play(),
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        );
      },
    );
  }
}

// ── AI Generator ─────────────────────────────────────────────────────────────

class _GeneratorTab extends ConsumerStatefulWidget {
  const _GeneratorTab();
  @override
  ConsumerState<_GeneratorTab> createState() => _GeneratorTabState();
}

class _GeneratorTabState extends ConsumerState<_GeneratorTab> {
  final _park = TextEditingController(text: 'Ocala National Forest');
  final _location = TextEditingController(text: 'Silver Glen Springs');
  final _lat = TextEditingController(text: '29.2461');
  final _lng = TextEditingController(text: '-81.6442');
  final _radius = TextEditingController(text: '150');
  StoryCategory _category = StoryCategory.springs;
  StoryAudience _audience = StoryAudience.general;
  int _count = 5;
  String? _voiceId;
  String? _voiceName;
  List<GeneratedStory> _drafts = const [];
  bool _saving = false;
  String? _message;

  @override
  void dispose() {
    _park.dispose();
    _location.dispose();
    _lat.dispose();
    _lng.dispose();
    _radius.dispose();
    super.dispose();
  }

  void _generate() {
    final drafts = StoryComposer(rng: Random()).generateVariations(
      location: _location.text.trim().isEmpty ? 'this spot' : _location.text.trim(),
      category: _category,
      count: _count,
      park: _park.text.trim().isEmpty ? 'the park' : _park.text.trim(),
    );
    setState(() {
      _drafts = drafts;
      _message = null;
    });
  }

  Future<void> _saveAll() async {
    if (_drafts.isEmpty) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final lat = double.tryParse(_lat.text.trim());
      final lng = double.tryParse(_lng.text.trim());
      final radius = int.tryParse(_radius.text.trim()) ?? 150;
      final entries = [
        for (final d in _drafts)
          StoryEntry(
            id: '',
            title: d.title,
            category: _category,
            parkId: _park.text.trim(),
            location: _location.text.trim(),
            variation: d.variation.label,
            collection: _location.text.trim(),
            latitude: lat,
            longitude: lng,
            triggerRadiusM: radius,
            transcript: d.transcript,
            voice: _voiceName,
            voiceId: _voiceId,
            audience: _audience.dbValue,
            status: StoryStatus.review,
          ),
      ];
      await ref.read(storyLibraryRepositoryProvider).insertMany(entries);
      ref.read(storyRefreshProvider.notifier).bump();
      setState(() {
        _message = 'Saved ${entries.length} drafts to the library for review. '
            'Approve them, generate audio (tool/story_audio.dart), then publish.';
        _saving = false;
        _drafts = const [];
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _message = 'Save failed (signed in? migration 0017 run?): $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voices = ref.watch(voicesProvider).value ?? const [];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'AI Story Generator',
          subtitle: 'Generate multiple varied drafts for a location, then review '
              'and approve them.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _f(_park, 'Park')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_location, 'Location')),
            ]),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<StoryCategory>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Category', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final c in StoryCategory.values)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                  ],
                  onChanged: (c) => setState(() => _category = c ?? _category),
                ),
              ),
              const Gap.h(AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<StoryAudience>(
                  initialValue: _audience,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Audience', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final a in StoryAudience.values)
                      DropdownMenuItem(value: a, child: Text(a.label)),
                  ],
                  onChanged: (a) => setState(() => _audience = a ?? _audience),
                ),
              ),
            ]),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(child: _f(_lat, 'Latitude')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_lng, 'Longitude')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_radius, 'Trigger radius (m)')),
            ]),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _voiceId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Voice', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final v in voices)
                      DropdownMenuItem(value: v.voiceId, child: Text(v.name)),
                  ],
                  onChanged: (id) {
                    if (id == null) return;
                    final v = voices.firstWhere((x) => x.voiceId == id);
                    setState(() {
                      _voiceId = v.voiceId;
                      _voiceName = v.name;
                    });
                  },
                ),
              ),
              const Gap.h(AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _count,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Variations', isDense: true, border: OutlineInputBorder()),
                  items: [
                    for (final n in [1, 5, 10, 25, 50])
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (n) => setState(() => _count = n ?? _count),
                ),
              ),
            ]),
            const Gap.v(AppSpacing.md),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _generate,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text('Generate $_count'),
              ),
              const Gap.h(AppSpacing.sm),
              if (_drafts.isNotEmpty)
                FilledButton.icon(
                  onPressed: _saving ? null : _saveAll,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text('Save ${_drafts.length} to library'),
                ),
            ]),
            if (_message != null) ...[
              const Gap.v(AppSpacing.sm),
              Text(_message!, style: theme.textTheme.bodySmall),
            ],
          ]),
        ),
        if (_drafts.isNotEmpty) ...[
          const Gap.v(AppSpacing.lg),
          AdminSectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_drafts.length} drafts (preview)',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Gap.v(AppSpacing.sm),
              for (final d in _drafts) ...[
                Text(d.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(d.transcript, style: theme.textTheme.bodySmall),
                const Divider(),
              ],
            ]),
          ),
        ],
      ],
    );
  }

  Widget _f(TextEditingController c, String label) => TextField(
      controller: c,
      decoration: InputDecoration(
          labelText: label, isDense: true, border: const OutlineInputBorder()));
}

// ── Approval Queue ────────────────────────────────────────────────────────────

class _ApprovalTab extends ConsumerWidget {
  const _ApprovalTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(storyLibraryProvider);
    final repo = ref.read(storyLibraryRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Approval Queue',
          subtitle: 'Review generated drafts. Edit the transcript if needed, then '
              'approve. Approved stories can be voiced and published.',
        ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Could not load.\n$e')),
          data: (all) {
            final pending = all.where((s) => !s.approved).toList();
            if (pending.isEmpty) {
              return const AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.check_circle_rounded,
                      message: 'Nothing waiting for review.'));
            }
            return Column(children: [
              for (final s in pending) ...[
                AdminSectionCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('${s.category.label}  ·  ${s.location ?? ''}',
                        style: theme.textTheme.bodySmall),
                    const Gap.v(AppSpacing.sm),
                    Text(s.transcript ?? '', style: theme.textTheme.bodyMedium),
                    const Gap.v(AppSpacing.md),
                    Row(children: [
                      FilledButton.icon(
                        onPressed: () async {
                          await repo.approve(s.id);
                          ref.read(storyRefreshProvider.notifier).bump();
                        },
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Approve'),
                      ),
                      const Gap.h(AppSpacing.sm),
                      TextButton.icon(
                        onPressed: () => _edit(context, ref, s),
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('Edit'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await repo.delete(s.id);
                          ref.read(storyRefreshProvider.notifier).bump();
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Reject'),
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

  void _edit(BuildContext context, WidgetRef ref, StoryEntry s) {
    final ctrl = TextEditingController(text: s.transcript ?? '');
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit — ${s.title}'),
        content: SizedBox(
          width: 480,
          child: TextField(
              controller: ctrl,
              maxLines: 8,
              decoration: const InputDecoration(border: OutlineInputBorder())),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(storyLibraryRepositoryProvider)
                  .updateTranscript(s.id, ctrl.text.trim());
              ref.read(storyRefreshProvider.notifier).bump();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ── GPS Zones ─────────────────────────────────────────────────────────────────

class _GpsZonesTab extends ConsumerWidget {
  const _GpsZonesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(storyLibraryProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'GPS Zones',
          subtitle: 'Trigger zones for each story. When a visitor enters a '
              'published story\'s radius, the app plays it.',
        ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (all) {
            final zoned = all.where((s) => s.hasCoordinates).toList();
            if (zoned.isEmpty) {
              return const AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.place_rounded,
                      message: 'No stories have coordinates yet. Set lat/lng when '
                          'generating.'));
            }
            return AdminSectionCard(
              child: Column(children: [
                for (final s in zoned) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.my_location_rounded,
                        color: s.playable ? Colors.teal : theme.disabledColor),
                    title: Text(s.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${s.latitude!.toStringAsFixed(4)}, '
                        '${s.longitude!.toStringAsFixed(4)}  ·  '
                        'r=${s.triggerRadiusM}m  ·  '
                        '${s.published ? "live" : "not published"}'),
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

// ── Collections ───────────────────────────────────────────────────────────────

class _CollectionsTab extends ConsumerWidget {
  const _CollectionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(storyLibraryProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Story Collections',
          subtitle: 'Stories grouped by collection (location or theme).',
        ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('$e'),
          data: (all) {
            final byCollection = <String, List<StoryEntry>>{};
            for (final s in all) {
              byCollection
                  .putIfAbsent(s.collection ?? 'Ungrouped', () => [])
                  .add(s);
            }
            if (byCollection.isEmpty) {
              return const AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.collections_bookmark_rounded,
                      message: 'No collections yet.'));
            }
            return Column(children: [
              for (final name in byCollection.keys) ...[
                AdminSectionCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$name (${byCollection[name]!.length})',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Gap.v(AppSpacing.xs),
                    for (final s in byCollection[name]!)
                      Text('• ${s.title}', style: theme.textTheme.bodySmall),
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
