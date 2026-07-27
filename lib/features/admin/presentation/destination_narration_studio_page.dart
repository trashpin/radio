import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/destinations/models/master_destination.dart';
import 'package:explorer_os_mobile/features/narration/data/destination_narration_repository.dart';
import 'package:explorer_os_mobile/features/narration/models/destination_narration.dart';
import 'package:explorer_os_mobile/features/narration/narration_qc.dart';

/// The per-destination AI Narration Studio: coverage header, generate actions,
/// and every script type with its variants, QC metrics, and lifecycle actions.
class DestinationNarrationStudioPage extends ConsumerWidget {
  const DestinationNarrationStudioPage({super.key, required this.destination});
  final MasterDestination destination;

  DestinationNarrationRepository _repo(WidgetRef ref) =>
      ref.read(destinationNarrationRepositoryProvider);

  Future<void> _generate(BuildContext context, WidgetRef ref, String mode) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo(ref).enqueueGenerate(
        destinationName: destination.name,
        category: destination.type,
        state: destination.state,
        county: destination.county,
        mode: mode,
      );
      messenger.showSnackBar(SnackBar(
          content: Text('Queued narration generation ($mode) for '
              '${destination.name}. Run the generator to process the job.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(destinationNarrationsProvider(destination.id));
    return Scaffold(
      appBar: AppBar(
        title: Text('Narration Studio · ${destination.name}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.read(narrationRefreshProvider.notifier).bump(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            AdminEmptyState(icon: Icons.error_outline_rounded, message: '$e'),
        data: (list) {
          final coverage = NarrationCoverage.fromList(list);
          final byType = <String, List<DestinationNarration>>{};
          for (final n in list) {
            byType.putIfAbsent(n.scriptType, () => []).add(n);
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            children: [
              _Header(destination: destination, coverage: coverage),
              const Gap.v(AppSpacing.md),
              _ActionBar(
                onGenerateAll: () => _generate(context, ref, 'all'),
                onGenerateMissing: () => _generate(context, ref, 'missing'),
              ),
              const Gap.v(AppSpacing.lg),
              Text('Script types',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Gap.v(AppSpacing.sm),
              for (final type in NarrationScriptType.values) ...[
                _ScriptTypeCard(
                  destination: destination,
                  type: type,
                  narrations: byType[type.dbValue] ?? const [],
                ),
                const Gap.v(AppSpacing.sm),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.destination, required this.coverage});
  final MasterDestination destination;
  final NarrationCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final img = destination.heroImage;
    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: AppRadius.mdAll,
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: (img != null && img.isNotEmpty)
                      ? Image.network(img,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _imgFallback(theme))
                      : _imgFallback(theme),
                ),
              ),
              const Gap.h(AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(destination.name,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const Gap.v(2),
                    Text(
                      [
                        if (destination.type != null) destination.type!,
                        if (destination.county != null) '${destination.county} County',
                        if (destination.state != null) destination.state!,
                      ].join('  ·  '),
                      style: theme.textTheme.bodySmall,
                    ),
                    const Gap.v(AppSpacing.sm),
                    Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: coverage.progress,
                            minHeight: 8,
                            backgroundColor:
                                theme.colorScheme.onSurface.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      const Gap.h(AppSpacing.sm),
                      Text('${(coverage.progress * 100).round()}%  '
                          '(${coverage.scriptTypes}/${NarrationScriptType.values.length} types)',
                          style: theme.textTheme.bodySmall),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const Gap.v(AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _stat('Scripts', '${coverage.scripts}', Icons.description_rounded),
              _stat('Audio', '${coverage.audioFiles}', Icons.graphic_eq_rounded),
              _stat('Approved', '${coverage.approved}', Icons.verified_rounded),
              _stat('Published', '${coverage.published}', Icons.public_rounded),
              if (coverage.needsReview > 0)
                _stat('Needs review', '${coverage.needsReview}',
                    Icons.report_gmailerrorred_rounded, const Color(0xFFC0392B)),
            ],
          ),
          if (coverage.lastGenerated != null) ...[
            const Gap.v(AppSpacing.sm),
            Text('Last generated ${_fmt(coverage.lastGenerated!)}   ·   '
                'Last updated ${_fmt(coverage.lastUpdated ?? coverage.lastGenerated!)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.disabledColor)),
          ],
        ],
      ),
    );
  }

  Widget _imgFallback(ThemeData theme) => Container(
        color: theme.colorScheme.primary.withValues(alpha: 0.14),
        child: Icon(Icons.record_voice_over_rounded,
            color: theme.colorScheme.primary),
      );

  Widget _stat(String label, String value, IconData icon, [Color? tint]) {
    return Builder(builder: (context) {
      final c = tint ?? Theme.of(context).colorScheme.primary;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: AppRadius.pillAll,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: c),
          const SizedBox(width: 6),
          Text('$value $label',
              style: TextStyle(
                  color: c, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      );
    });
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.onGenerateAll, required this.onGenerateMissing});
  final VoidCallback onGenerateAll;
  final VoidCallback onGenerateMissing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        FilledButton.icon(
          onPressed: onGenerateAll,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: const Text('Generate All'),
        ),
        OutlinedButton.icon(
          onPressed: onGenerateMissing,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
          icon: const Icon(Icons.playlist_add_rounded, size: 18),
          label: const Text('Generate Missing'),
        ),
      ],
    );
  }
}

class _ScriptTypeCard extends ConsumerWidget {
  const _ScriptTypeCard({
    required this.destination,
    required this.type,
    required this.narrations,
  });
  final MasterDestination destination;
  final NarrationScriptType type;
  final List<DestinationNarration> narrations;

  DestinationNarrationRepository _repo(WidgetRef ref) =>
      ref.read(destinationNarrationRepositoryProvider);

  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> fn,
      String ok) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await fn;
      ref.read(narrationRefreshProvider.notifier).bump();
      messenger.showSnackBar(SnackBar(content: Text(ok)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final has = narrations.isNotEmpty;
    return AdminSectionCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(type.icon, size: 20, color: theme.colorScheme.primary),
              const Gap.h(AppSpacing.sm),
              Expanded(
                child: Text(type.label,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text(
                  has
                      ? '${narrations.length}/${type.variations} versions'
                      : 'target ${type.variations}',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          if (!has) ...[
            const Gap.v(AppSpacing.xs),
            Row(children: [
              Text('Not generated yet',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.disabledColor)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _act(
                    context,
                    ref,
                    _repo(ref).enqueueGenerate(
                        destinationName: destination.name,
                        category: destination.type,
                        state: destination.state,
                        county: destination.county,
                        mode: type.dbValue),
                    'Queued ${type.label} generation'),
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('Generate'),
              ),
            ]),
          ],
          for (final n in narrations) _variantRow(context, ref, n),
        ],
      ),
    );
  }

  Widget _variantRow(BuildContext context, WidgetRef ref, DestinationNarration n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('v${n.variant}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Gap.h(AppSpacing.sm),
                  _statusChip(n),
                  if (n.needsReview) ...[
                    const Gap.h(AppSpacing.xs),
                    const Icon(Icons.report_gmailerrorred_rounded,
                        size: 14, color: Color(0xFFC0392B)),
                  ],
                ]),
                const Gap.v(2),
                Text(n.title ?? '(untitled)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
                Text(
                  '${n.wordCount} words · ${formatSeconds(n.speakingSeconds)} '
                  '${n.hasAudio ? '· audio ✓' : '· no audio'}'
                  '${n.duplicateScore != null ? ' · dup ${(n.duplicateScore! * 100).round()}%' : ''}'
                  '${n.readabilityScore != null ? ' · read ${n.readabilityScore!.round()}' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.disabledColor, fontSize: 11.5),
                ),
              ],
            ),
          ),
          _menu(context, ref, n),
        ],
      ),
    );
  }

  Widget _statusChip(DestinationNarration n) {
    final (color, text) = switch (n.status) {
      NarrationStatus.published => (const Color(0xFF2E7D32), 'Published'),
      NarrationStatus.approved => (const Color(0xFF2C6E8F), 'Approved'),
      NarrationStatus.needsReview => (const Color(0xFFC0392B), 'Needs review'),
      NarrationStatus.review => (const Color(0xFF8A6D00), 'Review'),
      NarrationStatus.draft => (const Color(0xFF9AA0A6), 'Draft'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: AppRadius.pillAll),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref, DestinationNarration n) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (v) {
        switch (v) {
          case 'preview':
            _preview(context, n);
          case 'edit':
            _edit(context, ref, n);
          case 'approve':
            _act(context, ref, _repo(ref).setStatus(n.id, NarrationStatus.approved),
                'Approved');
          case 'publish':
            _act(context, ref, _repo(ref).setStatus(n.id, NarrationStatus.published),
                'Published');
          case 'audio':
            _act(context, ref, _repo(ref).enqueueAudio(n), 'Queued audio generation');
          case 'copy':
            Clipboard.setData(ClipboardData(text: n.script ?? ''));
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Script copied to clipboard')));
          case 'delete':
            _act(context, ref, _repo(ref).deleteNarration(n.id), 'Deleted');
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'preview', child: Text('Preview')),
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'approve', child: Text('Approve')),
        PopupMenuItem(value: 'publish', child: Text('Publish')),
        PopupMenuItem(value: 'audio', child: Text('Generate Audio')),
        PopupMenuItem(value: 'copy', child: Text('Download Script (copy)')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  void _preview(BuildContext context, DestinationNarration n) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(n.title ?? type.label),
        content: SingleChildScrollView(child: Text(n.script ?? '(empty)')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  void _edit(BuildContext context, WidgetRef ref, DestinationNarration n) {
    final titleC = TextEditingController(text: n.title ?? '');
    final scriptC = TextEditingController(text: n.script ?? '');
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Edit narration'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: titleC,
                  decoration: const InputDecoration(
                      labelText: 'Title', border: OutlineInputBorder())),
              const Gap.v(AppSpacing.sm),
              TextField(
                controller: scriptC,
                maxLines: 10,
                decoration: const InputDecoration(
                    labelText: 'Script', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.of(dctx).pop();
              _act(
                  context,
                  ref,
                  _repo(ref).updateScript(n.id,
                      title: titleC.text.trim(), script: scriptC.text.trim()),
                  'Saved');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
