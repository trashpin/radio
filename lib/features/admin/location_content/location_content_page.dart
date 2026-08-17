import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/categories/category_repository.dart';
import 'package:explorer_os_mobile/features/admin/categories/location_category.dart';
import 'package:explorer_os_mobile/features/admin/discover_area/area_content_manager_page.dart';
import 'package:explorer_os_mobile/features/admin/geofence_manager_page.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/data/media_manager_repository.dart';
import 'package:explorer_os_mobile/features/admin/media_search/presentation/location_image_picker.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';
import 'package:explorer_os_mobile/features/locations/data/location_map_bridge.dart';
import 'package:explorer_os_mobile/features/locations/data/location_narration.dart';
import 'package:explorer_os_mobile/features/locations/data/location_narration_automation.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/location_health.dart';
import 'package:explorer_os_mobile/features/locations/media_match.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

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

class _OverviewTab extends ConsumerStatefulWidget {
  const _OverviewTab();
  @override
  ConsumerState<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends ConsumerState<_OverviewTab> {
  bool _generating = false;
  bool _importing = false;
  bool _wikimedia = false;

  /// Queues a Wikimedia Commons hero import for every location missing a hero
  /// (processed server-side by tool/wikimedia_import.py).
  Future<void> _importFromWikimedia(List<MasterLocation> all) async {
    final missing = all
        .where((l) => l.active && !l.hidden && l.images.isEmpty)
        .toList();
    if (missing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Every visible location already has a hero image.'),
        ),
      );
      return;
    }
    setState(() => _wikimedia = true);
    try {
      final n = await ref
          .read(locationRepositoryProvider)
          .enqueueWikimediaImport(missing);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Queued Wikimedia hero import for $n location(s).'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not queue: $e')));
      }
    } finally {
      if (mounted) setState(() => _wikimedia = false);
    }
  }

  /// Bulk photo import with auto-match: pick many images, match each to a
  /// location by filename (hero vs gallery), upload to storage, and attach.
  /// Unmatched files are reported as unassigned.
  Future<void> _bulkPhotoImport(List<MasterLocation> all) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    setState(() => _importing = true);
    final repo = ref.read(locationRepositoryProvider);
    final media = ref.read(mediaManagerRepositoryProvider);
    var matched = 0, unassigned = 0, failed = 0;
    // Track per-location image edits so multiple files stack correctly.
    final edits = <String, List<String>>{};
    List<String> current(MasterLocation l) => edits[l.id] ??= [...l.images];
    try {
      for (final f in res.files) {
        if (f.bytes == null) {
          failed++;
          continue;
        }
        final m = matchMediaToLocation(f.name, all);
        if (m.location == null) {
          unassigned++;
          continue;
        }
        try {
          final url = await media.upload(
            folder: 'locations',
            filename: '${DateTime.now().millisecondsSinceEpoch}_${f.name}',
            bytes: f.bytes!,
            contentType: 'image/jpeg',
          );
          final imgs = current(m.location!);
          if (m.isHero) {
            imgs
              ..remove(url)
              ..insert(0, url); // hero goes first
          } else {
            imgs.add(url);
          }
          matched++;
        } catch (_) {
          failed++;
        }
      }
      for (final entry in edits.entries) {
        await repo.update(entry.key, {'images': entry.value});
      }
      ref.read(locationRefreshProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported $matched photo(s) to '
              '${edits.length} location(s) · $unassigned unassigned'
              '${failed > 0 ? ' · $failed failed' : ''}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _generateMissingAudio(List<MasterLocation> all) async {
    final pending = all
        .where((l) => l.status == LocationStatus.pending)
        .toList();
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending locations — all narrated.')),
      );
      return;
    }
    setState(() => _generating = true);
    try {
      final n = await ref
          .read(locationRepositoryProvider)
          .enqueueMissingAudio(pending);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Queued audio generation for $n location(s).'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not queue jobs: $e')));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = ref.watch(masterLocationsProvider).value ?? const [];
    final health = computeLocationHealth(all);
    final showPending = ref.watch(showPendingLocationsProvider);
    final byType = <LocationType, int>{};
    for (final l in all) {
      byType[l.type] = (byType[l.type] ?? 0) + 1;
    }
    final sorted = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Widget stat(String label, int value, IconData icon, {Color? tint}) =>
        Expanded(
          child: AdminStatCard(
            label: label,
            value: '$value',
            icon: icon,
            tint: tint,
          ),
        );

    return _body(
      context,
      theme,
      all,
      health,
      showPending,
      byType,
      sorted,
      stat,
    );
  }

  Widget _pill(String label, int value, ThemeData theme, {Color? tint}) {
    final c = tint ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: c,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Gap.h(AppSpacing.xs),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ThemeData theme,
    List<MasterLocation> all,
    LocationHealth health,
    bool showPending,
    Map<LocationType, int> byType,
    List<MapEntry<LocationType, int>> sorted,
    Widget Function(String, int, IconData, {Color? tint}) stat,
  ) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Master Locations',
          subtitle:
              'One canonical location database. Users only see READY locations; '
              'PENDING need narration; DISABLED are hidden everywhere.',
          actions: [
            OutlinedButton.icon(
              onPressed: _wikimedia ? null : () => _importFromWikimedia(all),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: _wikimedia
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_search_rounded, size: 18),
              label: Text(_wikimedia ? 'Queuing…' : 'Import from Wikimedia'),
            ),
            const Gap.h(AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _importing ? null : () => _bulkPhotoImport(all),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_rounded, size: 18),
              label: Text(_importing ? 'Importing…' : 'Bulk Photo Import'),
            ),
            const Gap.h(AppSpacing.sm),
            FilledButton.icon(
              onPressed: _generating ? null : () => _generateMissingAudio(all),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.graphic_eq_rounded, size: 18),
              label: Text(_generating ? 'Queuing…' : 'Generate Missing Audio'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        // Narration progress.
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Narration progress',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(health.readyProgress * 100).toStringAsFixed(0)}% ready',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Gap.v(AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: health.readyProgress,
                  minHeight: 10,
                ),
              ),
              const Gap.v(AppSpacing.xs),
              Text(
                [
                  '${health.ready} ready',
                  '${health.pending} need narration',
                  if (health.lastGenerated != null)
                    'last generated ${_fmtDate(health.lastGenerated!)}',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const Gap.v(AppSpacing.md),
        Row(
          children: [
            stat('Total', health.total, Icons.public_rounded),
            const Gap.h(AppSpacing.md),
            stat(
              'Ready',
              health.ready,
              Icons.check_circle_rounded,
              tint: const Color(0xFF2E7D32),
            ),
            const Gap.h(AppSpacing.md),
            stat(
              'Needs narration',
              health.pending,
              Icons.mic_off_rounded,
              tint: const Color(0xFF8A6D00),
            ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        Row(
          children: [
            stat(
              'Missing audio',
              health.missingAudio,
              Icons.volume_off_rounded,
              tint: const Color(0xFFC0392B),
            ),
            const Gap.h(AppSpacing.md),
            stat(
              'Missing images',
              health.missingImages,
              Icons.image_not_supported_rounded,
            ),
            const Gap.h(AppSpacing.md),
            stat(
              'Missing coords',
              health.missingCoordinates,
              Icons.wrong_location_rounded,
            ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        Row(
          children: [
            stat(
              'Missing description',
              health.missingDescription,
              Icons.notes_rounded,
            ),
            const Gap.h(AppSpacing.md),
            stat(
              'Missing narration',
              health.missingNarration,
              Icons.record_voice_over_rounded,
            ),
            const Gap.h(AppSpacing.md),
            stat(
              'Broken audio',
              health.brokenAudio,
              Icons.link_off_rounded,
              tint: const Color(0xFFC0392B),
            ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        Row(
          children: [
            stat(
              'Broken audio',
              health.brokenAudio,
              Icons.link_off_rounded,
              tint: const Color(0xFFC0392B),
            ),
            const Gap.h(AppSpacing.md),
            stat(
              'Hidden / disabled',
              health.hidden,
              Icons.visibility_off_rounded,
            ),
            const Gap.h(AppSpacing.md),
            stat('Types in use', byType.length, Icons.category_rounded),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        Builder(
          builder: (_) {
            final img = computeImageHealth(all);
            return AdminSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Image health',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap.v(AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _pill('Total images', img.totalImages, theme),
                      _pill(
                        'With hero',
                        img.withHero,
                        theme,
                        tint: const Color(0xFF2E7D32),
                      ),
                      _pill(
                        'Missing / unassigned',
                        img.missingHero,
                        theme,
                        tint: const Color(0xFFC0392B),
                      ),
                      _pill('Missing gallery', img.missingGallery, theme),
                      _pill(
                        'Broken links',
                        img.brokenImageLinks,
                        theme,
                        tint: const Color(0xFFC0392B),
                      ),
                      _pill('Duplicates', img.duplicateImages, theme),
                      _pill(
                        '100% complete',
                        img.locationsComplete,
                        theme,
                        tint: const Color(0xFF2E7D32),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: showPending,
            onChanged: (v) =>
                ref.read(showPendingLocationsProvider.notifier).set(v),
            title: const Text('Show pending locations on the map'),
            subtitle: const Text(
              'Off by default — users only see narrated (Ready) locations.',
            ),
          ),
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'By type',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap.v(AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final e in sorted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${e.key.label} · ${e.value}',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
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
  MissingContent? _missing;
  String? _county;
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
        await repo.attachNarration(
          l.id,
          narrationIds: links.narrationIds,
          audioFiles: links.audioFiles,
        );
        linked++;
      }
      ref.read(locationRefreshProvider.notifier).bump();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Attached narration to $linked of ${items.length} '
              'location(s) from Location Content.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<MasterLocation> _filter(List<MasterLocation> all) {
    final q = _search.text.trim().toLowerCase();
    return all.where((l) {
      if (_type != null && l.type != _type) return false;
      if (_county != null && (l.county ?? '') != _county) return false;
      if (_missing != null && !locationIsMissing(l, _missing!)) return false;
      if (q.isEmpty) return true;
      return l.name.toLowerCase().contains(q) ||
          (l.county ?? '').toLowerCase().contains(q) ||
          (l.city ?? '').toLowerCase().contains(q) ||
          l.tags.any((t) => t.toLowerCase().contains(q)) ||
          l.type.label.toLowerCase().contains(q);
    }).toList();
  }

  /// Distinct, sorted county names present in the dataset (for the filter).
  List<String> _counties(List<MasterLocation> all) {
    final set = <String>{};
    for (final l in all) {
      final c = (l.county ?? '').trim();
      if (c.isNotEmpty) set.add(c);
    }
    final list = set.toList()..sort();
    return list;
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
          subtitle:
              'Create, edit, move, merge, upload media, attach narration, '
              'toggle map/radio visibility.',
          actions: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _attachAll(items),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
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
          child: Column(
            children: [
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search locations',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const Gap.v(AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<LocationType?>(
                      initialValue: _type,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All types'),
                        ),
                        for (final t in LocationType.values)
                          DropdownMenuItem(value: t, child: Text(t.label)),
                      ],
                      onChanged: (t) => setState(() => _type = t),
                    ),
                  ),
                  const Gap.h(AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _county,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'County',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All counties'),
                        ),
                        for (final c in _counties(async.value ?? const []))
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (c) => setState(() => _county = c),
                    ),
                  ),
                ],
              ),
              const Gap.v(AppSpacing.md),
              DropdownButtonFormField<MissingContent?>(
                initialValue: _missing,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Missing content',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Any (no filter)'),
                  ),
                  for (final m in MissingContent.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) => setState(() => _missing = m),
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
            message:
                'No locations. Tap New, or run migration 0031 to import '
                'existing POIs/destinations.',
            icon: Icons.wrong_location_rounded,
          )
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
      context: context,
      builder: (_) => _EditorDialog(item: item),
    );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No matching Location Content narration nearby.'),
          ),
        );
      }
      return;
    }
    await repo.attachNarration(
      item.id,
      narrationIds: links.narrationIds,
      audioFiles: links.audioFiles,
    );
    ref.read(locationRefreshProvider.notifier).bump();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attached ${links.narrationIds.length} narration(s), '
            '${links.audioFiles.length} audio file(s).',
          ),
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Merged "${item.name}" into "${target.name}".')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(locationRepositoryProvider);
    void refresh() => ref.read(locationRefreshProvider.notifier).bump();

    return AdminSectionCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.type.label,
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Gap.h(AppSpacing.sm),
                    switch (item.status) {
                      LocationStatus.ready => const StatusBadge(
                        BadgeStatus.published,
                        label: 'Ready',
                      ),
                      LocationStatus.pending => const StatusBadge(
                        BadgeStatus.review,
                        label: 'Needs Narration',
                      ),
                      LocationStatus.disabled => const StatusBadge(
                        BadgeStatus.draft,
                        label: 'Disabled',
                      ),
                    },
                    if (item.featured) ...[
                      const Gap.h(AppSpacing.xs),
                      const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: Color(0xFFE0A458),
                      ),
                    ],
                  ],
                ),
                const Gap.v(AppSpacing.xs),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  [
                    item.placeLine,
                    if (item.hasCoordinates)
                      '${item.latitude!.toStringAsFixed(3)}, ${item.longitude!.toStringAsFixed(3)}'
                    else
                      'no coordinates',
                    if ((item.source ?? '').isNotEmpty) 'from ${item.source}',
                  ].whereType<String>().join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                const Gap.v(AppSpacing.xs),
                Builder(
                  builder: (_) {
                    final c = completionFor(item);
                    Widget chk(String l, bool ok) => Text(
                      '${ok ? '✓' : '✗'} $l',
                      style: TextStyle(
                        fontSize: 11,
                        color: ok
                            ? const Color(0xFF2E7D32)
                            : theme.colorScheme.error,
                      ),
                    );
                    return Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        Text(
                          '${c.percent}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: c.complete
                                ? const Color(0xFF2E7D32)
                                : theme.colorScheme.primary,
                          ),
                        ),
                        chk('Hero', c.hero),
                        chk('Gallery', c.gallery),
                        chk('Narration', c.narration),
                        chk('GPS', c.gps),
                        chk('Map', c.map),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Find & save a photo',
            icon: Icon(
              item.images.isEmpty
                  ? Icons.add_a_photo_rounded
                  : Icons.image_search_rounded,
              color: item.images.isEmpty
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            onPressed: () => showLocationImagePicker(context, item),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  onEdit();
                case 'photo':
                  await showLocationImagePicker(context, item);
                case 'attach':
                  await _attach(context, ref);
                case 'merge':
                  await _merge(context, ref);
                case 'active':
                  await repo.update(item.id, {'active': !item.active});
                  refresh();
                case 'featured':
                  await repo.update(item.id, {'featured': !item.featured});
                  refresh();
                case 'hidden':
                  await repo.update(item.id, {'hidden': !item.hidden});
                  refresh();
                case 'delete':
                  await repo.delete(item.id);
                  refresh();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit / upload media'),
              ),
              const PopupMenuItem(
                value: 'photo',
                child: Text('Find & save a photo'),
              ),
              const PopupMenuItem(
                value: 'attach',
                child: Text('Attach narration'),
              ),
              const PopupMenuItem(value: 'merge', child: Text('Merge into…')),
              PopupMenuItem(
                value: 'active',
                child: Text(item.active ? 'Disable' : 'Enable'),
              ),
              PopupMenuItem(
                value: 'featured',
                child: Text(item.featured ? 'Unfeature' : 'Feature'),
              ),
              PopupMenuItem(
                value: 'hidden',
                child: Text(item.hidden ? 'Show on map' : 'Hide from map'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
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
        child: Column(
          children: [
            const Text(
              'The selected location keeps its record; this one\'s '
              'media + narration move onto it, then it is deleted.',
              style: TextStyle(fontSize: 12),
            ),
            const Gap.v(AppSpacing.sm),
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                labelText: 'Search target',
                isDense: true,
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
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
                          subtitle: Text(
                            [
                              l.type.label,
                              l.placeLine,
                            ].whereType<String>().join(' · '),
                          ),
                          onTap: () => Navigator.pop(context, l),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
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
  late final _community = TextEditingController(
    text: widget.item?.community ?? '',
  );
  late final _desc = TextEditingController(
    text: widget.item?.description ?? '',
  );
  late final _lat = TextEditingController(
    text: widget.item?.latitude?.toString() ?? '',
  );
  late final _lng = TextEditingController(
    text: widget.item?.longitude?.toString() ?? '',
  );
  late final _priority = TextEditingController(
    text: '${widget.item?.priority ?? 0}',
  );
  late final _trigger = TextEditingController(
    text: widget.item?.triggerRadius?.toString() ?? '',
  );
  late final _state = TextEditingController(text: widget.item?.state ?? '');
  late final _address = TextEditingController(text: widget.item?.address ?? '');
  late final _short = TextEditingController(
    text: widget.item?.shortDescription ?? '',
  );
  late final _long = TextEditingController(
    text: widget.item?.longDescription ?? '',
  );
  late final _script = TextEditingController(
    text: widget.item?.narrationScript ?? '',
  );
  late final _website = TextEditingController(
    text: widget.item?.externalWebsite ?? '',
  );
  late final _hours = TextEditingController(text: widget.item?.hours ?? '');
  late final _admission = TextEditingController(
    text: widget.item?.admission ?? '',
  );
  late final _parking = TextEditingController(
    text: widget.item?.parkingInfo ?? '',
  );
  late final _restrooms = TextEditingController(
    text: widget.item?.restrooms ?? '',
  );
  late final _difficulty = TextEditingController(
    text: widget.item?.difficulty ?? '',
  );
  late final _tags = TextEditingController(
    text: (widget.item?.tags ?? const []).join(', '),
  );
  late String _type = widget.item?.type.id ?? LocationType.pointOfInterest.id;
  late bool _active = widget.item?.active ?? true;
  late bool _featured = widget.item?.featured ?? false;
  late bool _hidden = widget.item?.hidden ?? false;
  late bool _familyFriendly = widget.item?.familyFriendly ?? false;
  late bool _petFriendly = widget.item?.petFriendly ?? false;
  late bool _wheelchair = widget.item?.wheelchairAccessible ?? false;
  late final List<String> _images = [...?widget.item?.images];
  late final List<String> _audio = [...?widget.item?.audioFiles];
  bool _saving = false;
  bool _uploading = false;
  NarrationAutomationResult? _narrationResult;
  MasterLocation? _lastSaved;

  @override
  void dispose() {
    for (final c in [
      _name,
      _county,
      _city,
      _community,
      _desc,
      _lat,
      _lng,
      _priority,
      _trigger,
      _state,
      _address,
      _short,
      _long,
      _script,
      _website,
      _hours,
      _admission,
      _parking,
      _restrooms,
      _difficulty,
      _tags,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _nn(String s) => s.trim().isEmpty ? null : s.trim();
  List<String> _parseTags(String s) =>
      s.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _narrationResult = null;
    });
    final repo = ref.read(locationRepositoryProvider);
    final row = <String, dynamic>{
      'name': _name.text.trim(),
      'category': _type,
      'latitude': double.tryParse(_lat.text.trim()),
      'longitude': double.tryParse(_lng.text.trim()),
      'county': _county.text.trim().isEmpty ? null : _county.text.trim(),
      'city': _city.text.trim().isEmpty ? null : _city.text.trim(),
      'community': _community.text.trim().isEmpty
          ? null
          : _community.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'priority': int.tryParse(_priority.text.trim()) ?? 0,
      'trigger_radius': double.tryParse(_trigger.text.trim()),
      'active': _active,
      'featured': _featured,
      'hidden': _hidden,
      'images': _images,
      'audio_files': _audio,
      // Richer PoI fields (dropped automatically if migration 0038 isn't applied).
      'state': _nn(_state.text),
      'address': _nn(_address.text),
      'short_description': _nn(_short.text),
      'long_description': _nn(_long.text),
      'narration_script': _nn(_script.text),
      'external_website': _nn(_website.text),
      'hours': _nn(_hours.text),
      'admission': _nn(_admission.text),
      'parking_info': _nn(_parking.text),
      'restrooms': _nn(_restrooms.text),
      'difficulty': _nn(_difficulty.text),
      'tags': _parseTags(_tags.text),
      'family_friendly': _familyFriendly,
      'pet_friendly': _petFriendly,
      'wheelchair_accessible': _wheelchair,
    };

    String? id;
    try {
      if (widget.item == null) {
        id = await repo.createAndReturnId({...row, 'source': 'manual'});
      } else {
        await repo.update(widget.item!.id, row);
        id = widget.item!.id;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
      return;
    }

    // The location record itself is saved at this point — refresh the list
    // right away so it's never lost even if narration generation below fails.
    ref.read(locationRefreshProvider.notifier).bump();

    if (id == null) {
      // Couldn't get an id back (e.g. Supabase not configured) — nothing to
      // automate; close exactly like before this feature existed.
      if (mounted) Navigator.pop(context, true);
      return;
    }

    await _runNarrationAutomation(MasterLocation.fromJson({...row, 'id': id}));
  }

  /// Drives the automated narration flow for [saved] and updates the dialog
  /// with each stage. Auto-closes on success/skip; stays open on failure so
  /// the admin can read the reason and retry without losing their save.
  Future<void> _runNarrationAutomation(MasterLocation saved) async {
    _lastSaved = saved;
    final automation = ref.read(locationNarrationAutomationProvider);
    await for (final result in automation.run(saved)) {
      if (!mounted) return;
      setState(() => _narrationResult = result);
    }
    if (!mounted) return;
    setState(() => _saving = false);

    if (_narrationResult?.isSuccess ?? true) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.pop(context, true);
    } else if (_narrationResult?.stage == NarrationAutomationStage.stillPending) {
      // Not a failure — nothing for the admin to decide here, just give them
      // time to read the longer explanation before closing on their behalf.
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _retryNarration() async {
    final saved = _lastSaved;
    if (saved == null) return;
    setState(() {
      _saving = true;
      _narrationResult = null;
    });
    await _runNarrationAutomation(saved);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'New location' : 'Edit location'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _f(_name, 'Name'),
              const Gap.v(AppSpacing.sm),
              Builder(builder: (context) {
                final options = ref.watch(categoryOptionsProvider);
                final knownIds = options.map((o) => o.id).toSet();
                final items = [
                  ...options,
                  // Defensive: if the location's current category isn't in
                  // the (active-only) merged list — e.g. it was deactivated,
                  // or custom categories haven't loaded yet — keep it
                  // selectable rather than crashing the dropdown.
                  if (!knownIds.contains(_type))
                    CategoryOption(id: _type, label: _type, isCustom: true),
                ];
                return DropdownButtonFormField<String>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final o in items)
                      DropdownMenuItem(
                        value: o.id,
                        child:
                            Text(o.isCustom ? '${o.label} (custom)' : o.label),
                      ),
                  ],
                  onChanged: (t) => setState(() => _type = t ?? _type),
                );
              }),
              if (_type == 'area' && widget.item != null) ...[
                const Gap.v(AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AreaContentManagerPage(
                      locationId: widget.item!.id,
                      areaName: _name.text.trim().isEmpty
                          ? widget.item!.name
                          : _name.text.trim(),
                    ),
                  )),
                  icon: const Icon(Icons.menu_book_rounded),
                  label: const Text('Manage Discovery Content (History, Nature, Geology...)'),
                ),
              ],
              if (widget.item != null) ...[
                const Gap.v(AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => GeofenceManagerPage(
                      locationId: widget.item!.id,
                      locationName: _name.text.trim().isEmpty
                          ? widget.item!.name
                          : _name.text.trim(),
                      defaultLat: widget.item!.latitude,
                      defaultLng: widget.item!.longitude,
                    ),
                  )),
                  icon: const Icon(Icons.public_rounded),
                  label: const Text('Manage Geofences (hierarchy, priority)'),
                ),
              ],
              const Gap.v(AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _f(_lat, 'Latitude')),
                  const Gap.h(AppSpacing.sm),
                  Expanded(child: _f(_lng, 'Longitude')),
                  const Gap.h(AppSpacing.sm),
                  SizedBox(width: 90, child: _f(_priority, 'Priority')),
                ],
              ),
              const Gap.v(AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _f(_state, 'State')),
                  const Gap.h(AppSpacing.sm),
                  Expanded(child: _f(_county, 'County')),
                ],
              ),
              const Gap.v(AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _f(_city, 'City')),
                  const Gap.h(AppSpacing.sm),
                  Expanded(child: _f(_community, 'Community')),
                ],
              ),
              const Gap.v(AppSpacing.sm),
              _f(_address, 'Street address'),
              const Gap.v(AppSpacing.sm),
              _f(_trigger, 'GPS trigger radius (meters)'),
              const Divider(height: AppSpacing.lg),
              _f(_short, 'Short description', maxLines: 2),
              const Gap.v(AppSpacing.sm),
              _f(_long, 'Long description', maxLines: 4),
              const Gap.v(AppSpacing.sm),
              _f(_desc, 'Description (legacy / fallback)', maxLines: 2),
              const Gap.v(AppSpacing.sm),
              _f(_script, 'Narration script (spoken)', maxLines: 4),
              const Divider(height: AppSpacing.lg),
              _mediaSection(),
              const Divider(height: AppSpacing.lg),
              // Visitor logistics
              _f(_website, 'External website'),
              const Gap.v(AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _f(_hours, 'Hours')),
                  const Gap.h(AppSpacing.sm),
                  Expanded(child: _f(_admission, 'Admission / fees')),
                ],
              ),
              const Gap.v(AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _f(_parking, 'Parking info')),
                  const Gap.h(AppSpacing.sm),
                  Expanded(child: _f(_restrooms, 'Restrooms')),
                ],
              ),
              const Gap.v(AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _f(_difficulty, 'Difficulty (if applicable)'),
                  ),
                  const Gap.h(AppSpacing.sm),
                  Expanded(child: _f(_tags, 'Tags (comma-separated)')),
                ],
              ),
              const Gap.v(AppSpacing.sm),
              Row(
                children: [
                  _toggle(
                    'Family',
                    _familyFriendly,
                    (v) => setState(() => _familyFriendly = v),
                  ),
                  _toggle(
                    'Pets',
                    _petFriendly,
                    (v) => setState(() => _petFriendly = v),
                  ),
                  _toggle(
                    'Wheelchair',
                    _wheelchair,
                    (v) => setState(() => _wheelchair = v),
                  ),
                ],
              ),
              const Divider(height: AppSpacing.lg),
              Row(
                children: [
                  _toggle(
                    'Active',
                    _active,
                    (v) => setState(() => _active = v),
                  ),
                  _toggle(
                    'Featured',
                    _featured,
                    (v) => setState(() => _featured = v),
                  ),
                  _toggle(
                    'Hidden',
                    _hidden,
                    (v) => setState(() => _hidden = v),
                  ),
                ],
              ),
              if (_narrationResult != null) ...[
                const Gap.v(AppSpacing.md),
                _narrationPanel(context, _narrationResult!),
              ],
            ],
          ),
        ),
      ),
      actions: (_narrationResult?.isGenuineFailure ?? false)
          ? [
              TextButton(
                onPressed: _saving ? null : _retryNarration,
                child: const Text('Retry Narration'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Close'),
              ),
            ]
          : [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ],
    );
  }

  Widget _narrationPanel(BuildContext context, NarrationAutomationResult r) {
    final theme = Theme.of(context);
    final color = r.stage == NarrationAutomationStage.failed
        ? theme.colorScheme.error
        : (r.isSuccess ? Colors.green : theme.colorScheme.primary);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!r.isTerminal)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Icon(
              r.isSuccess
                  ? Icons.check_circle_rounded
                  : (r.isGenuineFailure
                      ? Icons.error_rounded
                      : Icons.hourglass_top_rounded),
              color: color,
              size: 18,
            ),
          const Gap.h(AppSpacing.sm),
          Expanded(
            child: Text(
              r.message,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
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
      final url = await ref
          .read(mediaManagerRepositoryProvider)
          .upload(
            folder: image ? 'locations' : 'locations/audio',
            filename: '${DateTime.now().millisecondsSinceEpoch}_${file.name}',
            bytes: file.bytes!,
            contentType: image ? 'image/jpeg' : 'audio/mpeg',
          );
      setState(() => (image ? _images : _audio).add(url));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
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
            hintText: 'https://…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Add'),
          ),
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

  Widget _mediaRow(
    String label,
    IconData icon,
    List<String> urls, {
    required bool image,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18),
            const Gap.h(AppSpacing.xs),
            Text(
              '$label (${urls.length})',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
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
          ],
        ),
        for (final u in urls)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    u,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => urls.remove(u)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _f(TextEditingController c, String label, {int maxLines = 1}) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      Expanded(
        child: Row(
          children: [
            Switch(value: value, onChanged: onChanged),
            Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );
}
