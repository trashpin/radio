import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config_repository.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';

/// Admin → County Manager: edit each county's welcome greeting, description,
/// theme song, weather voice, weather/recommendation toggles, and its
/// recommendation library for the County Welcome & Weather Radio.
class CountyManagerPage extends ConsumerWidget {
  const CountyManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(countyConfigsProvider);
    final items = async.value ?? const <CountyConfig>[];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'County Manager',
          subtitle: 'County welcome greetings, weather, and recommendations '
              'for the travel-radio county reports.',
          actions: [
            FilledButton.icon(
              onPressed: () => _edit(context, ref),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add county'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        if (async.isLoading)
          const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()))
        else if (items.isEmpty)
          const AdminEmptyState(
              message: 'No counties yet. Run migration 0032, or Add county. '
                  'The radio uses built-in greetings until then.',
              icon: Icons.map_rounded)
        else
          for (final c in items) ...[
            _CountyCard(config: c, onEdit: () => _edit(context, ref, config: c)),
            const Gap.v(AppSpacing.sm),
          ],
      ],
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref,
      {CountyConfig? config}) async {
    final saved = await showDialog<bool>(
        context: context, builder: (_) => _CountyEditor(config: config));
    if (saved == true) ref.read(countyConfigRefreshProvider.notifier).bump();
  }
}

class _CountyCard extends ConsumerWidget {
  const _CountyCard({required this.config, required this.onEdit});
  final CountyConfig config;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AdminSectionCard(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('${config.name} County',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Gap.h(AppSpacing.sm),
              if (config.weatherEnabled)
                const StatusBadge(BadgeStatus.published, label: 'Weather on')
              else
                const StatusBadge(BadgeStatus.draft, label: 'Weather off'),
            ]),
            const Gap.v(AppSpacing.xs),
            Text(config.welcome ?? '(built-in greeting)',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall),
            if (config.recommendations.isNotEmpty)
              Text('${config.recommendations.length} custom recommendation(s)',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary)),
          ]),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) async {
            if (v == 'edit') onEdit();
            if (v == 'delete') {
              await ref
                  .read(countyConfigRepositoryProvider)
                  .delete(config.id);
              ref.read(countyConfigRefreshProvider.notifier).bump();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ]),
    );
  }
}

class _CountyEditor extends ConsumerStatefulWidget {
  const _CountyEditor({this.config});
  final CountyConfig? config;
  @override
  ConsumerState<_CountyEditor> createState() => _CountyEditorState();
}

class _CountyEditorState extends ConsumerState<_CountyEditor> {
  late final _name = TextEditingController(text: widget.config?.name ?? '');
  late final _state =
      TextEditingController(text: widget.config?.state ?? 'Florida');
  late final _welcome =
      TextEditingController(text: widget.config?.welcome ?? '');
  late final _desc =
      TextEditingController(text: widget.config?.description ?? '');
  late final _theme =
      TextEditingController(text: widget.config?.themeSongUrl ?? '');
  late final _voice =
      TextEditingController(text: widget.config?.weatherVoice ?? '');
  late final _recs = TextEditingController(
      text: (widget.config?.recommendations ?? const []).join('\n'));
  late bool _weather = widget.config?.weatherEnabled ?? true;
  late bool _recEnabled = widget.config?.recommendationsEnabled ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _state, _welcome, _desc, _theme, _voice, _recs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(countyConfigRepositoryProvider);
    final row = {
      'name': _name.text.trim(),
      'state': _state.text.trim(),
      'welcome': _welcome.text.trim().isEmpty ? null : _welcome.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'theme_song_url': _theme.text.trim().isEmpty ? null : _theme.text.trim(),
      'weather_voice': _voice.text.trim().isEmpty ? null : _voice.text.trim(),
      'weather_enabled': _weather,
      'recommendations_enabled': _recEnabled,
      'recommendations': _recs.text
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    };
    try {
      if (widget.config == null) {
        await repo.create(row);
      } else {
        await repo.update(widget.config!.id, row);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.config == null ? 'Add county' : 'Edit county'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: _f(_name, 'County name')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_state, 'State')),
            ]),
            const Gap.v(AppSpacing.sm),
            _f(_welcome, 'Welcome greeting', maxLines: 2),
            const Gap.v(AppSpacing.sm),
            _f(_desc, 'Description', maxLines: 2),
            const Gap.v(AppSpacing.sm),
            _f(_theme, 'County theme song URL'),
            const Gap.v(AppSpacing.sm),
            _f(_voice, 'Weather voice'),
            const Gap.v(AppSpacing.sm),
            _f(_recs, 'Recommendations (one per line)', maxLines: 4),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _weather,
                  onChanged: (v) => setState(() => _weather = v),
                  title: const Text('Weather', style: TextStyle(fontSize: 13)),
                ),
              ),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _recEnabled,
                  onChanged: (v) => setState(() => _recEnabled = v),
                  title: const Text('Recs', style: TextStyle(fontSize: 13)),
                ),
              ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }

  Widget _f(TextEditingController c, String label, {int maxLines = 1}) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
      );
}
