import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/data/media_manager_repository.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';
import 'package:explorer_os_mobile/features/locations/data/location_narration.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Admin → Locations. The ONE place to manage every master location that the
/// Map, Radio, GPS, "I See Something", Nearby, Narration, and Search all read.
class LocationsAdminPage extends StatelessWidget {
  const LocationsAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.dashboard_rounded), text: 'Overview'),
                Tab(icon: Icon(Icons.place_rounded), text: 'Locations'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [_OverviewTab(), _ListTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = ref.watch(masterLocationsProvider).value ?? const [];
    final active = all.where((l) => l.active && !l.hidden).length;
    final byType = <LocationType, int>{};
    for (final l in all) {
      byType[l.type] = (byType[l.type] ?? 0) + 1;
    }
    final sorted = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Master Locations',
          subtitle:
              'One canonical location database. Add a place once and it powers '
              'the map, radio, GPS triggers, nearby, narration, and search.',
        ),
        const Gap.v(AppSpacing.lg),
        Row(children: [
          Expanded(child: AdminStatCard(
              label: 'Total locations', value: '${all.length}',
              icon: Icons.public_rounded)),
          const Gap.h(AppSpacing.md),
          Expanded(child: AdminStatCard(
              label: 'Active on map', value: '$active',
              icon: Icons.map_rounded, tint: const Color(0xFF2E7D32))),
          const Gap.h(AppSpacing.md),
          Expanded(child: AdminStatCard(
              label: 'Types in use', value: '${byType.length}',
              icon: Icons.category_rounded)),
        ]),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('By type', style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
              const Gap.v(AppSpacing.md),
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                for (final e in sorted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${e.key.label} · ${e.value}',
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ],
          ),
        ),
      ],
    );
  }
}

class _ListTab extends ConsumerStatefulWidget {
  const _ListTab();
  @override
  ConsumerState<_ListTab> createState() => _ListTabState();
}

class _ListTabState extends ConsumerState<_ListTab> {
  final _search = TextEditingController();
  LocationType? _type;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Resolve + persist narration links (from Location Content) for the given
  /// locations, writing narration_ids + audio_files.
  Future<void> _attachAll(List<MasterLocation> items) async {
    setState(() => _busy = true);
    final repo = ref.read(locationRepositoryProvider);
    final content = ref.read(locationContentItemsProvider);
    var linked = 0;
    try {
      for (final l in items) {
        final links = resolveNarrationLinks(l, content);
        if (links.isEmpty) continue;
        await repo.attachNarration(l.id,
            narrationIds: links.narrationIds, audioFiles: links.audioFiles);
        linked++;
      }
      ref.read(locationRefreshProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Attached narration to $linked of ${items.length} '
                'location(s) from Location Content.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<MasterLocation> _filter(List<MasterLocation> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((l) {
      if (_type != null && l.type != _type) return false;
      if (q.isEmpty) return true;
      return l.name.toLowerCase().contains(q) ||
          (l.county ?? '').toLowerCase().contains(q) ||
          (l.city ?? '').toLowerCase().contains(q) ||
          l.type.label.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(masterLocationsProvider);
    final items = _filter(async.value ?? const []);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Locations',
          subtitle: 'Create, edit, move, merge, upload media, attach narration, '
              'toggle map/radio visibility.',
          actions: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _attachAll(items),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: _busy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link_rounded, size: 18),
              label: Text(_busy ? 'Attaching…' : 'Attach narration'),
            ),
            const Gap.h(AppSpacing.sm),
            FilledButton.icon(
              onPressed: () => _openEditor(context),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_location_alt_rounded, size: 18),
              label: const Text('New'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Search locations',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true, border: OutlineInputBorder()),
            ),
            const Gap.v(AppSpacing.md),
            DropdownButtonFormField<LocationType?>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Type', isDense: true, border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('All types')),
                for (final t in LocationType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) => setState(() => _type = t),
            ),
          ]),
        ),
        const Gap.v(AppSpacing.md),
        if (async.isLoading)
          const Padding(padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()))
        else if (items.isEmpty)
          const AdminEmptyState(
              message: 'No locations. Tap New, or run migration 0031 to import '
                  'existing POIs/destinations.',
              icon: Icons.wrong_location_rounded)
        else ...[
          Text('${items.length} location(s)', style: theme.textTheme.bodySmall),
          const Gap.v(AppSpacing.sm),
          for (final l in items) ...[
            _Row(
              item: l,
              all: async.value ?? const [],
              onEdit: () => _openEditor(context, item: l),
            ),
            const Gap.v(AppSpacing.sm),
          ],
        ],
      ],
    );
  }

  Future<void> _openEditor(BuildContext context, {MasterLocation? item}) async {
    final saved = await showDialog<bool>(
      context: context, builder: (_) => _EditorDialog(item: item));
    if (saved == true) ref.read(locationRefreshProvider.notifier).bump();
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.item, required this.all, required this.onEdit});
  final MasterLocation item;
  final List<MasterLocation> all;
  final VoidCallback onEdit;

  Future<void> _attach(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(locationRepositoryProvider);
    final content = ref.read(locationContentItemsProvider);
    final links = resolveNarrationLinks(item, content);
    if (links.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No matching Location Content narration nearby.')));
      }
      return;
    }
    await repo.attachNarration(item.id,
        narrationIds: links.narrationIds, audioFiles: links.audioFiles);
    ref.read(locationRefreshProvider.notifier).bump();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Attached ${links.narrationIds.length} narration(s), '
              '${links.audioFiles.length} audio file(s).')));
    }
  }

  Future<void> _merge(BuildContext context, WidgetRef ref) async {
    final target = await showDialog<MasterLocation>(
      context: context,
      builder: (_) => _MergePicker(current: item, all: all),
    );
    if (target == null) return;
    await ref.read(locationRepositoryProvider).merge(target, item);
    ref.read(locationRefreshProvider.notifier).bump();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Merged "${item.name}" into "${target.name}".')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(locationRepositoryProvider);
    void refresh() => ref.read(locationRefreshProvider.notifier).bump();

    return AdminSectionCard(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20)),
                child: Text(item.type.label, style: TextStyle(
                    color: theme.colorScheme.primary, fontSize: 11,
                    fontWeight: FontWeight.w600)),
              ),
              const Gap.h(AppSpacing.sm),
              if (!item.active || item.hidden)
                StatusBadge(BadgeStatus.draft,
                    label: item.hidden ? 'Hidden' : 'Inactive')
              else
                const StatusBadge(BadgeStatus.published, label: 'Live'),
              if (item.featured) ...[
                const Gap.h(AppSpacing.xs),
                const Icon(Icons.star_rounded, size: 16, color: Color(0xFFE0A458)),
              ],
            ]),
            const Gap.v(AppSpacing.xs),
            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text([
              item.placeLine,
              if (item.hasCoordinates)
                '${item.latitude!.toStringAsFixed(3)}, ${item.longitude!.toStringAsFixed(3)}'
              else 'no coordinates',
              if ((item.source ?? '').isNotEmpty) 'from ${item.source}',
            ].whereType<String>().join(' · '), style: theme.textTheme.bodySmall),
            if (item.narrationIds.isNotEmpty ||
                item.audioFiles.isNotEmpty ||
                item.images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text([
                  if (item.narrationIds.isNotEmpty)
                    '${item.narrationIds.length} narration',
                  if (item.audioFiles.isNotEmpty)
                    '${item.audioFiles.length} audio',
                  if (item.images.isNotEmpty) '${item.images.length} image',
                ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary)),
              ),
          ]),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) async {
            switch (v) {
              case 'edit': onEdit();
              case 'attach': await _attach(context, ref);
              case 'merge': await _merge(context, ref);
              case 'active':
                await repo.update(item.id, {'active': !item.active}); refresh();
              case 'featured':
                await repo.update(item.id, {'featured': !item.featured}); refresh();
              case 'hidden':
                await repo.update(item.id, {'hidden': !item.hidden}); refresh();
              case 'delete':
                await repo.delete(item.id); refresh();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit / upload media')),
            const PopupMenuItem(
                value: 'attach', child: Text('Attach narration')),
            const PopupMenuItem(value: 'merge', child: Text('Merge into…')),
            PopupMenuItem(value: 'active',
                child: Text(item.active ? 'Disable' : 'Enable')),
            PopupMenuItem(value: 'featured',
                child: Text(item.featured ? 'Unfeature' : 'Feature')),
            PopupMenuItem(value: 'hidden',
                child: Text(item.hidden ? 'Show on map' : 'Hide from map')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ]),
    );
  }
}

class _MergePicker extends StatefulWidget {
  const _MergePicker({required this.current, required this.all});
  final MasterLocation current;
  final List<MasterLocation> all;
  @override
  State<_MergePicker> createState() => _MergePickerState();
}

class _MergePickerState extends State<_MergePicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final candidates = widget.all
        .where((l) => l.id != widget.current.id)
        .where((l) => q.isEmpty || l.name.toLowerCase().contains(q))
        .take(40)
        .toList();
    return AlertDialog(
      title: Text('Merge "${widget.current.name}" into…'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(children: [
          const Text('The selected location keeps its record; this one\'s '
              'media + narration move onto it, then it is deleted.',
              style: TextStyle(fontSize: 12)),
          const Gap.v(AppSpacing.sm),
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
                labelText: 'Search target', isDense: true,
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder()),
          ),
          const Gap.v(AppSpacing.sm),
          Expanded(
            child: candidates.isEmpty
                ? const Center(child: Text('No matches'))
                : ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (_, i) {
                      final l = candidates[i];
                      return ListTile(
                        dense: true,
                        title: Text(l.name),
                        subtitle: Text([l.type.label, l.placeLine]
                            .whereType<String>()
                            .join(' · ')),
                        onTap: () => Navigator.pop(context, l),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
      ],
    );
  }
}

class _EditorDialog extends ConsumerStatefulWidget {
  const _EditorDialog({this.item});
  final MasterLocation? item;
  @override
  ConsumerState<_EditorDialog> createState() => _EditorDialogState();
}

class _EditorDialogState extends ConsumerState<_EditorDialog> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _county = TextEditingController(text: widget.item?.county ?? '');
  late final _city = TextEditingController(text: widget.item?.city ?? '');
  late final _community = TextEditingController(text: widget.item?.community ?? '');
  late final _desc = TextEditingController(text: widget.item?.description ?? '');
  late final _lat = TextEditingController(text: widget.item?.latitude?.toString() ?? '');
  late final _lng = TextEditingController(text: widget.item?.longitude?.toString() ?? '');
  late final _priority = TextEditingController(text: '${widget.item?.priority ?? 0}');
  late final _trigger = TextEditingController(
      text: widget.item?.triggerRadius?.toString() ?? '');
  late LocationType _type = widget.item?.type ?? LocationType.pointOfInterest;
  late bool _active = widget.item?.active ?? true;
  late bool _featured = widget.item?.featured ?? false;
  late bool _hidden = widget.item?.hidden ?? false;
  late final List<String> _images = [...?widget.item?.images];
  late final List<String> _audio = [...?widget.item?.audioFiles];
  bool _saving = false;
  bool _uploading = false;

  @override
  void dispose() {
    for (final c in [_name, _county, _city, _community, _desc, _lat, _lng,
        _priority, _trigger]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(locationRepositoryProvider);
    final row = <String, dynamic>{
      'name': _name.text.trim(),
      'category': _type.id,
      'latitude': double.tryParse(_lat.text.trim()),
      'longitude': double.tryParse(_lng.text.trim()),
      'county': _county.text.trim().isEmpty ? null : _county.text.trim(),
      'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
      'community': _community.text.trim().isEmpty ? null : _community.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'priority': int.tryParse(_priority.text.trim()) ?? 0,
      'trigger_radius': double.tryParse(_trigger.text.trim()),
      'active': _active,
      'featured': _featured,
      'hidden': _hidden,
      'images': _images,
      'audio_files': _audio,
    };
    try {
      if (widget.item == null) {
        await repo.create({...row, 'source': 'manual'});
      } else {
        await repo.update(widget.item!.id, row);
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
      title: Text(widget.item == null ? 'New location' : 'Edit location'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _f(_name, 'Name'),
            const Gap.v(AppSpacing.sm),
            DropdownButtonFormField<LocationType>(
              initialValue: _type,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Type', isDense: true, border: OutlineInputBorder()),
              items: [
                for (final t in LocationType.values)
                  DropdownMenuItem(value: t, child: Text(t.label)),
              ],
              onChanged: (t) => setState(() => _type = t ?? _type),
            ),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(child: _f(_lat, 'Latitude')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_lng, 'Longitude')),
              const Gap.h(AppSpacing.sm),
              SizedBox(width: 90, child: _f(_priority, 'Priority')),
            ]),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(child: _f(_county, 'County')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_city, 'City')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_community, 'Community')),
            ]),
            const Gap.v(AppSpacing.sm),
            _f(_trigger, 'Trigger radius (meters)'),
            const Gap.v(AppSpacing.sm),
            _f(_desc, 'Description', maxLines: 3),
            const Divider(height: AppSpacing.lg),
            _mediaSection(),
            const Divider(height: AppSpacing.lg),
            Row(children: [
              _toggle('Active', _active, (v) => setState(() => _active = v)),
              _toggle('Featured', _featured, (v) => setState(() => _featured = v)),
              _toggle('Hidden', _hidden, (v) => setState(() => _hidden = v)),
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

  Future<void> _uploadMedia({required bool image}) async {
    final res = await FilePicker.platform.pickFiles(
      type: image ? FileType.image : FileType.audio,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    if (file.bytes == null) return;
    setState(() => _uploading = true);
    try {
      final url = await ref.read(mediaManagerRepositoryProvider).upload(
            folder: image ? 'locations' : 'locations/audio',
            filename: '${DateTime.now().millisecondsSinceEpoch}_${file.name}',
            bytes: file.bytes!,
            contentType: image ? 'image/jpeg' : 'audio/mpeg',
          );
      setState(() => (image ? _images : _audio).add(url));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addByUrl({required bool image}) async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Add ${image ? 'image' : 'audio'} URL'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'https://…', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) {
      setState(() => (image ? _images : _audio).add(url));
    }
  }

  Widget _mediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _mediaRow('Images', Icons.image_rounded, _images, image: true),
        const Gap.v(AppSpacing.sm),
        _mediaRow('Audio', Icons.audiotrack_rounded, _audio, image: false),
      ],
    );
  }

  Widget _mediaRow(String label, IconData icon, List<String> urls,
      {required bool image}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 18),
          const Gap.h(AppSpacing.xs),
          Text('$label (${urls.length})',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton.icon(
            onPressed: _uploading ? null : () => _uploadMedia(image: image),
            icon: const Icon(Icons.upload_rounded, size: 16),
            label: const Text('Upload'),
          ),
          TextButton.icon(
            onPressed: () => _addByUrl(image: image),
            icon: const Icon(Icons.link_rounded, size: 16),
            label: const Text('URL'),
          ),
        ]),
        for (final u in urls)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              Expanded(
                child: Text(u,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() => urls.remove(u)),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _f(TextEditingController c, String label, {int maxLines = 1}) => TextField(
      controller: c, maxLines: maxLines,
      decoration: InputDecoration(
          labelText: label, isDense: true, border: const OutlineInputBorder()));

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      Expanded(
        child: Row(children: [
          Switch(value: value, onChanged: onChanged),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
        ]),
      );
}
