import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/location_content/location_content_admin_repository.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/ambient_sounds/models/ambient_sound.dart'
    show kAmbientSoundTypes;
import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart';

/// Admin → Location Content. One place to manage every geocoded "where you are"
/// narration (Counties, Cities, Communities, Rivers, Lakes, Scenic Roads,
/// Historic Sites, Forests, Parks, Springs, Attractions) backed by the unified
/// `location_content` index: create, edit, delete, preview, and manage audio.
class LocationContentPage extends StatelessWidget {
  const LocationContentPage({super.key});

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
                Tab(icon: Icon(Icons.dashboard_rounded), text: 'Dashboard'),
                Tab(icon: Icon(Icons.travel_explore_rounded), text: 'Library'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [_DashboardTab(), _LibraryTab()],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dashboard ────────────────────────────────────────────────────────────────

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(locationCollectionStatsProvider);
    final items = ref.watch(locationAdminItemsProvider).value ?? const [];
    final total = items.length;
    final withAudio =
        items.where((i) => (i.audioUrl ?? '').trim().isNotEmpty).length;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Location Content',
          subtitle:
              'Every geocoded narration the radio uses to tell the story of '
              'where the visitor is — organized into collections.',
        ),
        const Gap.v(AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AdminStatCard(
                label: 'Total narrations',
                value: '$total',
                icon: Icons.record_voice_over_rounded,
              ),
            ),
            const Gap.h(AppSpacing.md),
            Expanded(
              child: AdminStatCard(
                label: 'With audio',
                value: '$withAudio',
                icon: Icons.graphic_eq_rounded,
                tint: const Color(0xFF2E7D32),
              ),
            ),
            const Gap.h(AppSpacing.md),
            Expanded(
              child: AdminStatCard(
                label: 'Missing audio',
                value: '${total - withAudio}',
                icon: Icons.volume_off_rounded,
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
              Text('Collections',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Gap.v(AppSpacing.md),
              for (final col in LocationCollection.values)
                _collectionRow(theme, col, stats[col]!),
            ],
          ),
        ),
      ],
    );
  }

  Widget _collectionRow(ThemeData theme, LocationCollection col, CollectionStat s) {
    final pct = s.total == 0 ? 0.0 : s.withAudio / s.total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(col.label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: theme.dividerColor.withValues(alpha: 0.3),
                color: const Color(0xFF2E7D32),
              ),
            ),
          ),
          const Gap.h(AppSpacing.md),
          SizedBox(
            width: 90,
            child: Text('${s.withAudio}/${s.total} voiced',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall),
          ),
        ],
      ),
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
  LocationCollection? _collection;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ContentItem> _filter(List<ContentItem> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((i) {
      if (_collection != null && LocationCollection.of(i.category) != _collection) {
        return false;
      }
      if (q.isEmpty) return true;
      return i.title.toLowerCase().contains(q) ||
          (i.county ?? '').toLowerCase().contains(q) ||
          (i.city ?? '').toLowerCase().contains(q) ||
          i.category.id.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(locationAdminItemsProvider);
    final items = _filter(async.value ?? const []);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Library',
          subtitle: 'Create, edit, preview, and manage narration audio.',
          actions: [
            FilledButton.icon(
              onPressed: () => _openEditor(context),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            children: [
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const Gap.v(AppSpacing.md),
              DropdownButtonFormField<LocationCollection?>(
                initialValue: _collection,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Collection',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All collections')),
                  for (final c in LocationCollection.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (c) => setState(() => _collection = c),
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
        else if (items.isEmpty)
          const AdminEmptyState(
              message: 'No location content. Tap New, or seed a county with the '
                  'tools.',
              icon: Icons.travel_explore_rounded)
        else ...[
          Text('${items.length} item(s)', style: theme.textTheme.bodySmall),
          const Gap.v(AppSpacing.sm),
          for (final i in items) ...[
            _Row(item: i, onEdit: () => _openEditor(context, item: i)),
            const Gap.v(AppSpacing.sm),
          ],
        ],
      ],
    );
  }

  Future<void> _openEditor(BuildContext context, {ContentItem? item}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditorDialog(item: item),
    );
    if (saved == true) ref.read(locationAdminRefreshProvider.notifier).bump();
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.item, required this.onEdit});
  final ContentItem item;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(locationContentAdminRepositoryProvider);
    void refresh() => ref.read(locationAdminRefreshProvider.notifier).bump();
    final hasAudio = (item.audioUrl ?? '').trim().isNotEmpty;

    return AdminSectionCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(item.category.id,
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                  const Gap.h(AppSpacing.sm),
                  StatusBadge(hasAudio ? BadgeStatus.published : BadgeStatus.draft,
                      label: hasAudio ? 'Voiced' : 'No audio'),
                ]),
                const Gap.v(AppSpacing.xs),
                Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text([
                  if ((item.city ?? '').isNotEmpty) item.city,
                  if ((item.county ?? '').isNotEmpty) '${item.county} County',
                  item.state,
                ].whereType<String>().join(' · '),
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  onEdit();
                case 'preview':
                  await showDialog<void>(
                      context: context,
                      builder: (_) => _PreviewDialog(item: item));
                case 'generate_audio':
                  final queued = await repo.enqueueContentAudio(item.id);
                  if (queued) await repo.triggerNarrationWorker();
                  refresh();
                case 'revoice':
                  await repo.clearAudio(item.id);
                  refresh();
                case 'delete':
                  await repo.delete(item.id);
                  refresh();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'preview', child: Text('Preview')),
              if (!hasAudio)
                const PopupMenuItem(
                    value: 'generate_audio', child: Text('Generate Audio')),
              if (hasAudio)
                const PopupMenuItem(
                    value: 'revoice', child: Text('Clear audio (re-voice)')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Preview ──────────────────────────────────────────────────────────────────

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.item});
  final ContentItem item;
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
    final url = widget.item.audioUrl;
    if (url == null || url.isEmpty) return;
    _player ??= AudioPlayer();
    try {
      await _player!.setUrl(url);
      setState(() => _playing = true);
      await _player!.play();
    } catch (_) {}
    if (mounted) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    return AlertDialog(
      title: Text(i.title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i.category.id, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            Text('"${i.text ?? '(no narration text)'}"',
                style: const TextStyle(fontStyle: FontStyle.italic, height: 1.4)),
            if ((i.audioUrl ?? '').isNotEmpty) ...[
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

// ── Create / Edit ─────────────────────────────────────────────────────────────

class _EditorDialog extends ConsumerStatefulWidget {
  const _EditorDialog({this.item});
  final ContentItem? item;
  @override
  ConsumerState<_EditorDialog> createState() => _EditorDialogState();
}

class _EditorDialogState extends ConsumerState<_EditorDialog> {
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _county = TextEditingController(text: widget.item?.county ?? '');
  late final _city = TextEditingController(text: widget.item?.city ?? '');
  late final _state =
      TextEditingController(text: widget.item?.state ?? 'Florida');
  late final _park = TextEditingController(text: widget.item?.park ?? '');
  late final _lat =
      TextEditingController(text: widget.item?.latitude.toString() ?? '');
  late final _lng =
      TextEditingController(text: widget.item?.longitude.toString() ?? '');
  late final _priority =
      TextEditingController(text: '${widget.item?.basePriority ?? 0}');
  late final _text = TextEditingController(text: widget.item?.text ?? '');
  late ContentCategory _category =
      widget.item?.category ?? ContentCategory.countyWelcome;
  late String? _ambientType = widget.item?.ambientType;
  bool _saving = false;

  static final _editable = ContentCategory.values
      .where((c) => !const {
            ContentCategory.music,
            ContentCategory.dj,
            ContentCategory.stationId,
          }.contains(c))
      .toList();

  @override
  void dispose() {
    for (final c in [_title, _county, _city, _state, _park, _lat, _lng,
        _priority, _text]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(locationContentAdminRepositoryProvider);
    final row = <String, dynamic>{
      'title': _title.text.trim(),
      'category': _category.id,
      'latitude': double.tryParse(_lat.text.trim()) ?? 0,
      'longitude': double.tryParse(_lng.text.trim()) ?? 0,
      'county': _county.text.trim().isEmpty ? null : _county.text.trim(),
      'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
      'state': _state.text.trim().isEmpty ? null : _state.text.trim(),
      'park': _park.text.trim().isEmpty ? null : _park.text.trim(),
      'priority': int.tryParse(_priority.text.trim()) ?? 0,
      'text': _text.text.trim().isEmpty ? null : _text.text.trim(),
      'ambient_type': _ambientType,
    };
    try {
      if (widget.item == null) {
        await repo.create(row);
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
      title: Text(widget.item == null ? 'New location content' : 'Edit'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _f(_title, 'Title / Name'),
              const Gap.v(AppSpacing.sm),
              DropdownButtonFormField<ContentCategory>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Category',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: [
                  for (final c in _editable)
                    DropdownMenuItem(value: c, child: Text(c.id)),
                ],
                onChanged: (c) => setState(() => _category = c ?? _category),
              ),
              const Gap.v(AppSpacing.sm),
              Row(children: [
                Expanded(child: _f(_county, 'County')),
                const Gap.h(AppSpacing.sm),
                Expanded(child: _f(_city, 'City')),
              ]),
              const Gap.v(AppSpacing.sm),
              Row(children: [
                Expanded(child: _f(_state, 'State')),
                const Gap.h(AppSpacing.sm),
                Expanded(child: _f(_park, 'Park')),
              ]),
              const Gap.v(AppSpacing.sm),
              Row(children: [
                Expanded(child: _f(_lat, 'Latitude')),
                const Gap.h(AppSpacing.sm),
                Expanded(child: _f(_lng, 'Longitude')),
                const Gap.h(AppSpacing.sm),
                SizedBox(width: 90, child: _f(_priority, 'Priority')),
              ]),
              const Gap.v(AppSpacing.sm),
              _f(_text, 'Narration text', maxLines: 4),
              const Gap.v(AppSpacing.sm),
              DropdownButtonFormField<String?>(
                initialValue: _ambientType,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Ambient sound (optional)',
                    helperText: 'A very quiet background layer under this '
                        "narration, e.g. flowing water. Leave as \"None\" "
                        "unless it genuinely fits — don't force one.",
                    helperMaxLines: 2,
                    isDense: true,
                    border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final t in kAmbientSoundTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _ambientType = v),
              ),
            ],
          ),
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

  Widget _f(TextEditingController c, String label, {int maxLines = 1}) => TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
      );
}
