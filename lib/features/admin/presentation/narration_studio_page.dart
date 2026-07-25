import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/narration/data/narration_repository.dart';
import 'package:explorer_os_mobile/features/narration/models/narration.dart';
import 'package:explorer_os_mobile/features/narration/models/narration_type.dart';
import 'package:explorer_os_mobile/features/narration/services/narration_script_composer.dart';

/// Admin → AI Narration Studio: generate, edit, and organize pre-generated
/// narration scripts for every content record. Scripts are composed from record
/// data (deterministic; no AI call at runtime); audio generation (ElevenLabs)
/// is a key-gated step wired behind a seam.
class NarrationStudioPage extends ConsumerStatefulWidget {
  const NarrationStudioPage({super.key});

  @override
  ConsumerState<NarrationStudioPage> createState() =>
      _NarrationStudioPageState();
}

class _NarrationStudioPageState extends ConsumerState<NarrationStudioPage> {
  static const _composer = NarrationScriptComposer();
  final _drafts = <String, Narration>{}; // content_id -> narration
  String _query = '';
  String _filter = 'all'; // all | missing_script | missing_audio | complete
  bool _loadedExisting = false;
  String? _banner;

  Future<void> _loadExisting(List<Species> species) async {
    if (_loadedExisting) return;
    _loadedExisting = true;
    try {
      final repo = ref.read(narrationRepositoryProvider);
      for (final s in species) {
        final n = await repo.bestForContent(s.id);
        if (n != null) _drafts[s.id] = n;
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _banner =
            'The narrations table isn\'t present yet — run migration '
            '0007_narrations.sql to persist. You can still generate & edit scripts here.');
      }
    }
  }

  Narration _generate(Species s,
      {NarrationType type = NarrationType.standardRanger}) {
    final script = _composer.composeForSpecies(s, type: type);
    final existing = _drafts[s.id];
    return (existing ??
            Narration(
              id: existing?.id ?? '',
              contentId: s.id,
              contentType: 'species',
              parkId: s.destinationId,
              title: s.commonName,
              narrationType: type,
            ))
        .copyWith(
      script: script,
      narrationType: type,
      duration: _composer.estimateSeconds(script),
      status: 'draft',
    );
  }

  Future<void> _save(Narration n) async {
    try {
      final saved = await ref.read(narrationRepositoryProvider).upsert(n);
      setState(() => _drafts[n.contentId] = saved);
      _snack('Saved narration for ${n.title}');
    } catch (e) {
      setState(() => _drafts[n.contentId] = n); // keep locally
      _snack('Saved locally (run migration 0007 to persist): $e');
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  List<Species> _visible(List<Species> all) {
    return all.where((s) {
      final n = _drafts[s.id];
      switch (_filter) {
        case 'missing_script':
          if (n?.hasScript ?? false) return false;
        case 'missing_audio':
          if (n?.hasAudio ?? false) return false;
        case 'complete':
          if (!((n?.hasScript ?? false) && (n?.hasAudio ?? false))) {
            return false;
          }
      }
      if (_query.isEmpty) return true;
      return s.commonName.toLowerCase().contains(_query) ||
          s.category.toLowerCase().contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final speciesAsync = ref.watch(allSpeciesProvider);
    final species = speciesAsync.value ?? const <Species>[];
    if (species.isNotEmpty) _loadExisting(species);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'AI Narration Studio',
          subtitle: 'Generate, edit, and store narration for every record',
          actions: [
            OutlinedButton.icon(
              onPressed: species.isEmpty ? null : () => _bulkDialog(species),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
              icon: const Icon(Icons.auto_awesome_motion_rounded, size: 18),
              label: const Text('Bulk generate'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        if (_banner != null) ...[
          AdminSectionCard(
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: Colors.orange),
              const Gap.h(AppSpacing.md),
              Expanded(child: Text(_banner!)),
            ]),
          ),
          const Gap.v(AppSpacing.lg),
        ],
        _dashboard(species),
        const Gap.v(AppSpacing.lg),
        _searchBar(),
        const Gap.v(AppSpacing.md),
        if (speciesAsync.isLoading)
          const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator())),
        if (speciesAsync.hasError)
          AdminSectionCard(
            child: AdminEmptyState(
              icon: Icons.error_outline_rounded,
              message: 'Could not load content records.\n${speciesAsync.error}',
            ),
          ),
        if (species.isNotEmpty) _list(_visible(species)),
      ],
    );
  }

  Widget _dashboard(List<Species> species) {
    final total = species.length;
    final scripts = species.where((s) => _drafts[s.id]?.hasScript ?? false).length;
    final audio = species.where((s) => _drafts[s.id]?.hasAudio ?? false).length;
    final durations = _drafts.values
        .where((n) => n.duration != null)
        .map((n) => n.duration!)
        .toList();
    final avg = durations.isEmpty
        ? 0
        : (durations.reduce((a, b) => a + b) / durations.length).round();
    final pct = total == 0 ? 0 : ((scripts / total) * 100).round();
    final stats = <(String, String, Color)>[
      ('Total', '$total', Colors.blueGrey),
      ('Scripts complete', '$scripts', Colors.green),
      ('Audio complete', '$audio', Colors.teal),
      ('Missing scripts', '${total - scripts}', Colors.orange),
      ('Missing audio', '${total - audio}', Colors.red),
      ('Avg duration', '${avg}s', Colors.indigo),
      ('Scripts %', '$pct%', Colors.purple),
    ];
    return AdminSectionCard(
      child: Wrap(
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        children: [
          for (final (label, value, color) in stats)
            _stat(label, value, color),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, color: color)),
        Text(label, style: theme.textTheme.bodySmall),
      ]),
    );
  }

  Widget _searchBar() {
    return Row(children: [
      Expanded(
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Search by name or category…',
            prefixIcon: Icon(Icons.search_rounded),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v.toLowerCase()),
        ),
      ),
      const Gap.h(AppSpacing.md),
      DropdownButton<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v ?? 'all'),
        items: const [
          DropdownMenuItem(value: 'all', child: Text('All')),
          DropdownMenuItem(
              value: 'missing_script', child: Text('Missing script')),
          DropdownMenuItem(value: 'missing_audio', child: Text('Missing audio')),
          DropdownMenuItem(value: 'complete', child: Text('Complete')),
        ],
      ),
    ]);
  }

  Widget _list(List<Species> rows) {
    final theme = Theme.of(context);
    if (rows.isEmpty) {
      return const AdminSectionCard(
          child: AdminEmptyState(
              message: 'No matching records.', icon: Icons.search_off_rounded));
    }
    return AdminSectionCard(
      child: Column(children: [
        for (final s in rows)
          Builder(builder: (context) {
            final n = _drafts[s.id];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.commonName,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text([
                s.category,
                n?.hasScript ?? false
                    ? 'script ✓ (${n!.duration ?? 0}s)'
                    : 'no script',
                n?.hasAudio ?? false ? 'audio ✓' : 'no audio',
                if (n?.approved ?? false) 'approved',
              ].join('  ·  ')),
              trailing: Wrap(spacing: AppSpacing.sm, children: [
                if (!(n?.hasScript ?? false))
                  TextButton(
                    onPressed: () =>
                        setState(() => _drafts[s.id] = _generate(s)),
                    child: const Text('Generate'),
                  )
                else
                  TextButton(
                      onPressed: () => _editDialog(s), child: const Text('Edit')),
              ]),
            );
          }),
      ]),
    );
  }

  Future<void> _editDialog(Species s) async {
    var n = _drafts[s.id] ?? _generate(s);
    final controller = TextEditingController(text: n.script ?? '');
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final words = _composer.wordCount(controller.text);
        final secs = _composer.estimateSeconds(controller.text);
        return AlertDialog(
          title: Text('Narration — ${s.commonName}'),
          content: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                DropdownButton<NarrationType>(
                  value: n.narrationType,
                  onChanged: (t) {
                    if (t == null) return;
                    final script = _composer.composeForSpecies(s, type: t);
                    controller.text = script;
                    setLocal(() => n = n.copyWith(
                        narrationType: t,
                        script: script,
                        duration: _composer.estimateSeconds(script)));
                  },
                  items: [
                    for (final t in NarrationType.values)
                      DropdownMenuItem(value: t, child: Text(t.label)),
                  ],
                ),
                const Spacer(),
                Text('$words words · ~${secs}s',
                    style: Theme.of(ctx).textTheme.bodySmall),
              ]),
              const Gap.v(AppSpacing.sm),
              TextField(
                controller: controller,
                maxLines: 12,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), labelText: 'Script'),
              ),
              const Gap.v(AppSpacing.sm),
              Row(children: [
                Tooltip(
                  message: 'Requires ELEVENLABS_API_KEY + a server function.',
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                    label: const Text('Generate audio (ElevenLabs)'),
                  ),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _save(n.copyWith(
                    script: controller.text,
                    duration: _composer.estimateSeconds(controller.text),
                    approved: true,
                    status: 'published'));
              },
              child: const Text('Approve & Save'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _save(n.copyWith(
                    script: controller.text,
                    duration: _composer.estimateSeconds(controller.text)));
              },
              child: const Text('Save draft'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _bulkDialog(List<Species> species) async {
    final cats = species.map((s) => s.category).toSet().toList()..sort();
    final selected = <String>{...cats};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Bulk generate scripts'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Select categories to generate narration scripts for:'),
            const Gap.v(AppSpacing.sm),
            for (final c in cats)
              CheckboxListTile(
                dense: true,
                value: selected.contains(c),
                title: Text('$c '
                    '(${species.where((s) => s.category == c).length})'),
                onChanged: (v) => setLocal(() =>
                    v == true ? selected.add(c) : selected.remove(c)),
              ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _runBulk(species.where((s) => selected.contains(s.category)));
              },
              child: const Text('Generate scripts'),
            ),
          ],
        );
      }),
    );
  }

  void _runBulk(Iterable<Species> targets) {
    var n = 0;
    setState(() {
      for (final s in targets) {
        if (!(_drafts[s.id]?.hasScript ?? false)) {
          _drafts[s.id] = _generate(s);
          n++;
        }
      }
    });
    _snack('Generated $n scripts. Open a record to edit/approve, then Save.');
  }
}
