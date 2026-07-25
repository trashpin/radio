import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/image_match/image_match_service.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';

/// Admin → Image Matching: bulk-match uploaded images to species by filename.
///
/// Filenames are normalized to a `match_key` (see [ImageMatchService]) and
/// matched against the species catalog. Matched images are uploaded + linked;
/// multi-matches prompt a selection dialog; unmatched images go to a queue for
/// manual assignment. Real file bytes come from a browser file input in
/// production; here filenames drive the deterministic matching engine.
class ImageMatchingPage extends ConsumerStatefulWidget {
  const ImageMatchingPage({super.key});

  @override
  ConsumerState<ImageMatchingPage> createState() => _ImageMatchingPageState();
}

const _sampleBatch = 'Saw Palmetto.jpg\n'
    'Sand Pine.png\n'
    'Longleaf Pine.jpeg\n'
    'Prickly Pear Cactus.JPG\n'
    'Florida Black Bear.jpg\n'
    'Bald Eagle.png';

class _ImageMatchingPageState extends ConsumerState<ImageMatchingPage> {
  static const _service = ImageMatchService();
  final _controller = TextEditingController(text: _sampleBatch);
  bool _replaceExisting = false;
  ImportReport? _report;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(List<Species> species) {
    final candidates = _controller.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((name) => ImageCandidate(filename: name))
        .toList();
    setState(() {
      _report = _service.classify(candidates, species,
          replaceExisting: _replaceExisting);
    });
  }

  Future<void> _resolveMulti(MatchRow row) async {
    final picked = await showDialog<Species>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Multiple matches for "${row.candidate.filename}"'),
        children: [
          for (final s in row.matches)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: ListTile(
                leading: const Icon(Icons.eco_rounded),
                title: Text(s.commonName),
                subtitle: Text(s.scientificName ?? s.category),
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      setState(() {
        row.species = picked;
        row.matches = const [];
        row.status = MatchStatus.matched;
        row.note = 'resolved from ${_report!.multiMatch + 1} matches';
      });
    }
  }

  Future<void> _assignUnmatched(MatchRow row, List<Species> species) async {
    final picked = await showDialog<Species>(
      context: context,
      builder: (ctx) {
        final search = ValueNotifier('');
        return AlertDialog(
          title: Text('Assign "${row.candidate.filename}"'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: 'Search species…',
                      prefixIcon: Icon(Icons.search_rounded)),
                  onChanged: (v) => search.value = v.toLowerCase(),
                ),
                const Gap.v(AppSpacing.sm),
                SizedBox(
                  height: 280,
                  child: ValueListenableBuilder<String>(
                    valueListenable: search,
                    builder: (context, q, child) {
                      final results = species
                          .where((s) =>
                              q.isEmpty ||
                              s.commonName.toLowerCase().contains(q))
                          .toList();
                      return ListView(
                        children: [
                          for (final s in results)
                            ListTile(
                              dense: true,
                              title: Text(s.commonName),
                              subtitle: Text(s.category),
                              onTap: () => Navigator.pop(ctx, s),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        row.species = picked;
        row.status = MatchStatus.matched;
        row.note = 'manually assigned';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speciesAsync = ref.watch(allSpeciesProvider);
    final species = speciesAsync.value ?? const <Species>[];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Image Matching',
          subtitle:
              'Bulk-match uploaded images to species by filename (match_key)',
          actions: [
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _controller.text = _sampleBatch;
                _report = null;
              }),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: const Text('Sample batch'),
            ),
            const Gap.h(AppSpacing.sm),
            FilledButton.icon(
              onPressed: species.isEmpty ? null : () => _run(species),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Match images'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Uploaded images',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                'In production, an admin picks image files and their names are '
                'read here. Paste filenames (one per line) to run the matcher. '
                'Loaded species catalog: ${species.length}.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
              const Gap.v(AppSpacing.md),
              TextField(
                controller: _controller,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Image filenames',
                  hintText: 'Florida Black Bear.jpg',
                  border: OutlineInputBorder(),
                ),
              ),
              const Gap.v(AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _replaceExisting,
                onChanged: (v) => setState(() => _replaceExisting = v),
                title: const Text('Replace existing images'),
                subtitle: const Text(
                    'Off: matched species that already have an image are skipped.'),
              ),
            ],
          ),
        ),
        if (speciesAsync.isLoading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (speciesAsync.hasError)
          AdminSectionCard(
            child: AdminEmptyState(
              icon: Icons.error_outline_rounded,
              message: 'Could not load species catalog.\n'
                  'Run migration 0004_species.sql (and 0006 for match_key).\n'
                  '${speciesAsync.error}',
            ),
          ),
        if (_report != null) ...[
          const Gap.v(AppSpacing.lg),
          _ReportSummary(report: _report!),
          const Gap.v(AppSpacing.lg),
          _ReportList(
            report: _report!,
            service: _service,
            onResolve: _resolveMulti,
            onAssign: (row) => _assignUnmatched(row, species),
          ),
        ],
      ],
    );
  }
}

class _ReportSummary extends StatelessWidget {
  const _ReportSummary({required this.report});
  final ImportReport report;

  @override
  Widget build(BuildContext context) {
    final stats = <(String, int, Color)>[
      ('Matched', report.matched, Colors.green),
      ('Uploaded', report.uploaded, Colors.teal),
      ('Updated', report.updated, Colors.blue),
      ('Skipped', report.skipped, Colors.orange),
      ('Unmatched', report.unmatched, Colors.red),
    ];
    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Import report',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Gap.v(AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final (label, value, color) in stats)
                _StatChip(label: label, value: value, color: color),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800, color: color)),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({
    required this.report,
    required this.service,
    required this.onResolve,
    required this.onAssign,
  });
  final ImportReport report;
  final ImageMatchService service;
  final void Function(MatchRow) onResolve;
  final void Function(MatchRow) onAssign;

  ({IconData icon, Color color, String label}) _style(MatchStatus s) {
    switch (s) {
      case MatchStatus.matched:
      case MatchStatus.uploaded:
        return (icon: Icons.check_circle_rounded, color: Colors.green, label: 'Matched');
      case MatchStatus.multiMatch:
        return (icon: Icons.help_rounded, color: Colors.amber, label: 'Multiple');
      case MatchStatus.skipped:
        return (icon: Icons.skip_next_rounded, color: Colors.orange, label: 'Skipped');
      case MatchStatus.unmatched:
        return (icon: Icons.report_gmailerrorred_rounded, color: Colors.red, label: 'Unmatched');
      case MatchStatus.failed:
        return (icon: Icons.error_rounded, color: Colors.red, label: 'Failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdminSectionCard(
      child: Column(
        children: [
          for (final row in report.rows)
            Builder(builder: (context) {
              final st = _style(row.status);
              final path = row.species == null
                  ? null
                  : service.storagePath(
                      row.species!.destinationId, row.species!.category, row.candidate);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(st.icon, color: st.color),
                title: Text(row.candidate.filename,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  'match_key: ${row.candidate.matchKey}',
                  if (row.species != null) '→ ${row.species!.commonName}',
                  if (path != null) 'storage: species_images/$path',
                  if (row.note != null) row.note!,
                ].join('  ·  '),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: row.status == MatchStatus.multiMatch
                    ? TextButton(
                        onPressed: () => onResolve(row),
                        child: const Text('Resolve'))
                    : row.status == MatchStatus.unmatched
                        ? TextButton(
                            onPressed: () => onAssign(row),
                            child: const Text('Assign'))
                        : Chip(
                            label: Text(st.label),
                            backgroundColor: st.color.withValues(alpha: 0.12),
                            side: BorderSide(
                                color: st.color.withValues(alpha: 0.3)),
                          ),
              );
            }),
        ],
      ),
    );
  }
}
