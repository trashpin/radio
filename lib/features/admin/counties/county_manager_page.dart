import 'package:file_picker/file_picker.dart';
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
              const Gap.h(AppSpacing.sm),
              StatusBadge(
                config.profileCompleteness >= 1
                    ? BadgeStatus.published
                    : BadgeStatus.draft,
                label:
                    'Profile ${(config.profileCompleteness * 100).round()}%',
              ),
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
  late final _music = TextEditingController(
      text: (widget.config?.musicCategories ?? const []).join(', '));
  late bool _weather = widget.config?.weatherEnabled ?? true;
  late bool _recEnabled = widget.config?.recommendationsEnabled ?? true;

  // County Profile fields (read by TELL ME MORE's county tier).
  late final _seal = TextEditingController(text: widget.config?.sealUrl ?? '');
  late final _hero =
      TextEditingController(text: widget.config?.heroImageUrl ?? '');
  late final _welcomeNarration = TextEditingController(
      text: widget.config?.welcomeNarrationUrl ?? '');
  late final _history =
      TextEditingController(text: widget.config?.history ?? '');
  late final _overview =
      TextEditingController(text: widget.config?.overview ?? '');
  late final _population = TextEditingController(
      text: widget.config?.population?.toString() ?? '');
  late final _sizeSqMiles = TextEditingController(
      text: widget.config?.sizeSqMiles?.toString() ?? '');
  late final _yearEstablished = TextEditingController(
      text: widget.config?.yearEstablished?.toString() ?? '');
  late final _facts =
      TextEditingController(text: (widget.config?.facts ?? const []).join('\n'));
  late final _tourismInfo =
      TextEditingController(text: widget.config?.tourismInfo ?? '');
  late final _officialWebsite =
      TextEditingController(text: widget.config?.officialWebsite ?? '');
  late final _galleryImages = TextEditingController(
      text: (widget.config?.galleryImages ?? const []).join('\n'));

  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _state,
      _welcome,
      _desc,
      _theme,
      _voice,
      _recs,
      _music,
      _seal,
      _hero,
      _welcomeNarration,
      _history,
      _overview,
      _population,
      _sizeSqMiles,
      _yearEstablished,
      _facts,
      _tourismInfo,
      _officialWebsite,
      _galleryImages,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage(TextEditingController target) async {
    final res =
        await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final url = await ref
          .read(countyConfigRepositoryProvider)
          .uploadImage(res.files.first.bytes!, res.files.first.name);
      setState(() => target.text = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nn(String s) => s.trim().isEmpty ? null : s.trim();
  List<String> _lines(String s) =>
      s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(countyConfigRepositoryProvider);
    final row = {
      'name': _name.text.trim(),
      'state': _state.text.trim(),
      'welcome': _nn(_welcome.text),
      'description': _nn(_desc.text),
      'theme_song_url': _nn(_theme.text),
      'weather_voice': _nn(_voice.text),
      'weather_enabled': _weather,
      'recommendations_enabled': _recEnabled,
      'recommendations': _lines(_recs.text),
      'music_categories': _music.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'seal_url': _nn(_seal.text),
      'hero_image_url': _nn(_hero.text),
      'welcome_narration_url': _nn(_welcomeNarration.text),
      'history': _nn(_history.text),
      'overview': _nn(_overview.text),
      'population': int.tryParse(_population.text.trim()),
      'size_sq_miles': double.tryParse(_sizeSqMiles.text.trim()),
      'year_established': int.tryParse(_yearEstablished.text.trim()),
      'facts': _lines(_facts.text),
      'tourism_info': _nn(_tourismInfo.text),
      'official_website': _nn(_officialWebsite.text),
      'gallery_images': _lines(_galleryImages.text),
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
        width: 560,
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
            _f(_music,
                'Music categories (comma-separated, e.g. country, americana, southern)'),
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
            const Divider(height: 32),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('County Profile',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const Gap.v(AppSpacing.xs),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Read by TELL ME MORE when a traveler is out in open country '
                '(no event/park/spring/town nearby).',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(child: _imagePick(_seal, 'Seal image URL')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _imagePick(_hero, 'Hero image URL')),
            ]),
            const Gap.v(AppSpacing.sm),
            _f(_welcomeNarration, 'Welcome narration audio URL'),
            const Gap.v(AppSpacing.sm),
            _f(_history, 'History', maxLines: 3),
            const Gap.v(AppSpacing.sm),
            _f(_overview, 'Overview', maxLines: 3),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(child: _f(_population, 'Population')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_sizeSqMiles, 'Size (sq mi)')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_yearEstablished, 'Year established')),
            ]),
            const Gap.v(AppSpacing.sm),
            _f(_facts, 'Fun facts (one per line)', maxLines: 3),
            const Gap.v(AppSpacing.sm),
            _f(_tourismInfo, 'Tourism info', maxLines: 2),
            const Gap.v(AppSpacing.sm),
            _f(_officialWebsite, 'Official website'),
            const Gap.v(AppSpacing.sm),
            _f(_galleryImages, 'Gallery image URLs (one per line)',
                maxLines: 3),
            if (_saving) ...[
              const Gap.v(AppSpacing.sm),
              const LinearProgressIndicator(),
            ],
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

  Widget _imagePick(TextEditingController c, String label) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _f(c, label)),
          const Gap.h(AppSpacing.xs),
          IconButton(
            tooltip: 'Upload',
            onPressed: _saving ? null : () => _pickImage(c),
            icon: const Icon(Icons.upload_rounded),
          ),
        ],
      );
}
