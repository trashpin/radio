import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' hide AudioSource;

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/audio_recall/audio_recall.dart';
import 'package:explorer_os_mobile/features/admin/audio_recall/audio_recall_repository.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/presentation/widgets/media_widgets.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';

/// Admin → Audio Recall: one searchable inventory across every audio catalog so
/// nothing is ever lost, orphaned, or silently duplicated.
class AudioRecallPage extends ConsumerStatefulWidget {
  const AudioRecallPage({super.key});

  @override
  ConsumerState<AudioRecallPage> createState() => _AudioRecallPageState();
}

class _AudioRecallPageState extends ConsumerState<AudioRecallPage> {
  String _query = '';
  AudioSource? _source;
  bool _withFileOnly = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(audioInventoryProvider);
    final stats = ref.watch(audioInventoryStatsProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Audio Recall',
          subtitle: 'Every audio asset across all catalogs — searchable, '
              'de-duplicated, and play-tracked.',
          actions: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => ref.read(audioRecallRefreshProvider.notifier).bump(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Rescan'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 200).floor().clamp(2, 5);
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.6,
            children: [
              AdminStatCard(label: 'Total assets', value: '${stats.total}', icon: Icons.inventory_2_rounded),
              AdminStatCard(label: 'With audio file', value: '${stats.withFile}', icon: Icons.audiotrack_rounded, tint: const Color(0xFF2E7D32)),
              AdminStatCard(label: 'Scripts (no audio)', value: '${stats.orphanScripts}', icon: Icons.description_rounded, tint: const Color(0xFF8A6D00)),
              AdminStatCard(label: 'Duplicates', value: '${stats.duplicates}', icon: Icons.file_copy_rounded, tint: const Color(0xFFB3261E)),
              AdminStatCard(label: 'Total plays', value: '${stats.totalPlays}', icon: Icons.play_circle_rounded, tint: const Color(0xFF2C6E8F)),
            ],
          );
        }),
        const Gap.v(AppSpacing.md),
        _bySource(theme, stats),
        const Gap.v(AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                  hintText: 'Search title / voice / destination / tag…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<AudioSource?>(
                initialValue: _source,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Source', isDense: true, border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All sources')),
                  for (final s in AudioSource.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _source = v),
              ),
            ),
            FilterChip(
              label: const Text('Has audio only'),
              selected: _withFileOnly,
              onSelected: (v) => setState(() => _withFileOnly = v),
            ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Could not load inventory.\n$e')),
          data: (items) {
            final filtered = searchInventory(items,
                query: _query, source: _source, withFileOnly: _withFileOnly);
            final dupes = duplicateInventoryUrls(items);
            return AdminSectionCard(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: AdminEmptyState(
                          icon: Icons.library_music_rounded,
                          message: 'No audio matches your filters.'))
                  : Column(children: [
                      _header(theme),
                      for (final i in filtered.take(400))
                        _row(theme, i, isDuplicate(i, dupes)),
                    ]),
            );
          },
        ),
      ],
    );
  }

  Widget _bySource(ThemeData theme, AudioInventoryStats stats) {
    return AdminSectionCard(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final s in AudioSource.values)
            if ((stats.bySource[s] ?? 0) > 0)
              MediaStatusBadge('${s.label}: ${stats.bySource[s]}',
                  tone: MediaBadgeTone.info),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final st = theme.textTheme.labelSmall
        ?.copyWith(fontWeight: FontWeight.w800, color: theme.disabledColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(children: [
        Expanded(flex: 3, child: Text('TITLE', style: st)),
        SizedBox(width: 120, child: Text('SOURCE', style: st)),
        Expanded(flex: 2, child: Text('CATEGORY', style: st)),
        SizedBox(width: 70, child: Text('PLAYS', style: st)),
        SizedBox(width: 90, child: Text('STATUS', style: st)),
        SizedBox(width: 40, child: Text('', style: st)),
      ]),
    );
  }

  Widget _row(ThemeData theme, AudioInventoryItem i, bool dup) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)))),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(children: [
              Icon(i.hasFile ? Icons.audiotrack_rounded : Icons.description_outlined,
                  size: 16,
                  color: i.hasFile ? const Color(0xFF2E7D32) : theme.disabledColor),
              const Gap.h(AppSpacing.sm),
              Expanded(
                child: Text(i.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (dup) ...[
                const Gap.h(AppSpacing.xs),
                const MediaStatusBadge('DUP', tone: MediaBadgeTone.missing),
              ],
            ]),
          ),
          SizedBox(
              width: 120,
              child: Text(i.source.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall)),
          Expanded(
              flex: 2,
              child: Text(
                  [i.category, if (i.voice != null) i.voice]
                      .whereType<String>()
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall)),
          SizedBox(width: 70, child: Text('${i.playCount}', style: theme.textTheme.bodySmall)),
          SizedBox(
            width: 90,
            child: Text(i.status ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: i.hasFile ? 'Preview' : 'No audio yet',
              onPressed: i.hasFile ? () => _preview(i) : null,
              icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Delete',
              onPressed: () => _delete(i),
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(AudioInventoryItem i) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this audio?'),
        content: Text(
            'Remove "${i.displayTitle}" (${i.source.label}) permanently? '
            'This deletes it from the ${i.source.table} catalog'
            '${(i.storagePath ?? '').isNotEmpty ? ' and storage' : ''}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok =
        await ref.read(audioRecallRepositoryProvider).delete(i);
    if (ok) ref.read(audioRecallRefreshProvider.notifier).bump();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'Deleted "${i.displayTitle}"'
              : 'Could not delete "${i.displayTitle}"')));
    }
  }

  void _preview(AudioInventoryItem i) {
    if (i.source == AudioSource.audioAssets) {
      ref.read(audioRecallRepositoryProvider).recordPlay(i.id, usedBy: 'audio_recall');
    }
    showDialog<void>(
      context: context,
      builder: (_) => _PreviewDialog(url: i.publicUrl!, title: i.displayTitle),
    );
  }
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.url, required this.title});
  final String url;
  final String title;
  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  final _player = AudioPlayer();
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.setUrl(widget.url).then((_) => _player.play()).catchError((e) {
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
    return AlertDialog(
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      content: _error != null
          ? Text('Could not play: $_error')
          : StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (_, snap) {
                final playing = snap.data?.playing ?? false;
                return IconButton(
                  iconSize: 48,
                  onPressed: () => playing ? _player.pause() : _player.play(),
                  icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                );
              },
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}
