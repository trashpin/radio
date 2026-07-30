import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/admin/media_manager/data/media_manager_repository.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/admin/media_search/data/image_import_service.dart';
import 'package:explorer_os_mobile/features/admin/media_search/data/image_search_service.dart';
import 'package:explorer_os_mobile/features/admin/media_search/data/media_search_providers.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/image_filters.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/search_query.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Per-tab search state.
class _Search {
  const _Search({this.loading = false, this.error, this.outcome});
  final bool loading;
  final String? error;
  final SearchOutcome? outcome;
}

/// The Media Search Center — the single place to discover, preview, import,
/// organize, and manage every image ExplorerOS uses.
class MediaSearchCenterPage extends ConsumerStatefulWidget {
  const MediaSearchCenterPage({super.key});
  @override
  ConsumerState<MediaSearchCenterPage> createState() =>
      _MediaSearchCenterPageState();
}

class _MediaSearchCenterPageState extends ConsumerState<MediaSearchCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  final Map<ImageSource, _Search> _state = {
    ImageSource.openverse: const _Search(),
    ImageSource.wikimedia: const _Search(),
  };

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  SearchDestination? get _dest {
    final d = ref.read(selectedMediaDestinationProvider);
    if (d == null) return null;
    return SearchDestination(
      name: d.name,
      county: d.county,
      state: 'Florida',
      typeLabel: d.type.label,
    );
  }

  Future<void> _run(ImageSource source) async {
    final dest = _dest;
    if (dest == null) {
      _snack('Pick a destination first.');
      return;
    }
    setState(() => _state[source] = const _Search(loading: true));
    try {
      final outcome =
          await ref.read(imageSearchServiceProvider).smartSearch(source, dest);
      setState(() => _state[source] = _Search(outcome: outcome));
    } catch (e) {
      setState(() => _state[source] = _Search(error: '$e'));
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Icon(Icons.image_search_rounded,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Text('Media Search Center',
                  style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
        _dashboard(),
        _destinationBar(),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Openverse'),
            Tab(text: 'Wikimedia Commons'),
            Tab(text: 'Existing Media Library'),
            Tab(text: 'Upload My Own'),
            Tab(text: 'Recently Imported'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _searchTab(ImageSource.openverse),
              _searchTab(ImageSource.wikimedia),
              const _MediaLibraryTab(),
              const _UploadTab(),
              const _RecentlyImportedTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Dashboard ─────────────────────────────────────────────────────────────
  Widget _dashboard() {
    final d = ref.watch(mediaSearchDashboardProvider);
    final tiles = <(IconData, String, String)>[
      (Icons.photo_library_rounded, '${d.imagesImported}', 'Images imported'),
      (Icons.sd_storage_rounded, d.storageLabel, 'Storage used'),
      (Icons.hide_image_rounded, '${d.missingHero}', 'Missing hero image'),
      (Icons.location_off_rounded, '${d.destinationsWithoutPhotos}',
          'Destinations without photos'),
      (Icons.new_releases_rounded, '${d.recentlyImported}', 'Imported (7 days)'),
      (Icons.copyright_rounded, '${d.missingAttribution}',
          'Missing attribution'),
    ];
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final (icon, value, label) = tiles[i];
          return Container(
            width: 190,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(value,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Destination selector ────────────────────────────────────────────────
  Widget _destinationBar() {
    final selected = ref.watch(selectedMediaDestinationProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.place_rounded),
              style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size(0, 48)),
              onPressed: _pickDestination,
              label: Text(
                selected == null
                    ? 'Select a destination…'
                    : '${selected.name}'
                        '${selected.county == null ? '' : '  ·  ${selected.county} County'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (selected != null) ...[
            const SizedBox(width: 10),
            Text('${selected.images.length} photo(s)',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDestination() async {
    final all = ref.read(masterLocationsProvider).value ?? const [];
    final picked = await showDialog<MasterLocation>(
      context: context,
      builder: (_) => _DestinationPickerDialog(all: all),
    );
    if (picked != null) {
      ref.read(selectedMediaDestinationProvider.notifier).select(picked);
    }
  }

  // ── Search tab (Openverse / Wikimedia) ─────────────────────────────────────
  Widget _searchTab(ImageSource source) {
    final s = _state[source]!;
    final filters = ref.watch(imageFiltersProvider);
    final dest = ref.watch(selectedMediaDestinationProvider);
    return Column(
      children: [
        _FilterBar(
          onSearch: () => _run(source),
          searching: s.loading,
        ),
        if (s.outcome != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Matched query: "${s.outcome!.matchedQuery}"',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        Expanded(child: _searchBody(source, s, filters, dest)),
      ],
    );
  }

  Widget _searchBody(ImageSource source, _Search s, ImageFilters filters,
      MasterLocation? dest) {
    if (s.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s.error != null) {
      return _centered(Icons.error_outline_rounded,
          'Search failed', s.error!);
    }
    if (s.outcome == null) {
      return _centered(Icons.search_rounded, 'Search ${source.label}',
          dest == null
              ? 'Pick a destination, then Search.'
              : 'Search open-license photos for "${dest.name}".');
    }
    final ranked =
        filters.apply(s.outcome!.results, destinationName: dest?.name ?? '');
    if (ranked.isEmpty) {
      return _centered(Icons.filter_alt_off_rounded, 'No matching images',
          'Try relaxing the filters (min resolution / orientation / license).');
    }
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: ranked.length,
      itemBuilder: (_, i) => _ResultCard(
        result: ranked[i],
        onTap: () => _preview(ranked[i]),
      ),
    );
  }

  Widget _centered(IconData icon, String title, String body) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: Theme.of(context).disabledColor),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );

  Future<void> _preview(ImageSearchResult r) async {
    final dest = ref.read(selectedMediaDestinationProvider);
    if (dest == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PreviewDialog(
        result: r,
        destination: dest,
        onImported: (msg) {
          ref.read(locationRefreshProvider.notifier).bump();
          ref.invalidate(mediaAssetsProvider);
          _snack(msg);
        },
      ),
    );
  }
}

// ── Destination picker ───────────────────────────────────────────────────────
class _DestinationPickerDialog extends StatefulWidget {
  const _DestinationPickerDialog({required this.all});
  final List<MasterLocation> all;
  @override
  State<_DestinationPickerDialog> createState() =>
      _DestinationPickerDialogState();
}

class _DestinationPickerDialogState extends State<_DestinationPickerDialog> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final items = widget.all
        .where((l) =>
            q.isEmpty ||
            l.name.toLowerCase().contains(q) ||
            (l.county ?? '').toLowerCase().contains(q))
        .take(200)
        .toList();
    return AlertDialog(
      title: const Text('Select a destination'),
      content: SizedBox(
        width: 460,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search by name or county…',
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('No matches'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final l = items[i];
                        final hasHero =
                            l.images.any((u) => u.trim().isNotEmpty);
                        return ListTile(
                          leading: Icon(hasHero
                              ? Icons.image_rounded
                              : Icons.hide_image_outlined),
                          title: Text(l.name),
                          subtitle: Text([
                            l.type.label,
                            if (l.county != null) '${l.county} County',
                          ].join(' · ')),
                          trailing: Text('${l.images.length}'),
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
            onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

// ── Filter bar ───────────────────────────────────────────────────────────────
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.onSearch, required this.searching});
  final VoidCallback onSearch;
  final bool searching;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(imageFiltersProvider);
    final n = ref.read(imageFiltersProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<OrientationFilter>(
            segments: const [
              ButtonSegment(
                  value: OrientationFilter.any, label: Text('Any')),
              ButtonSegment(
                  value: OrientationFilter.landscape,
                  label: Text('Landscape')),
              ButtonSegment(
                  value: OrientationFilter.portrait, label: Text('Portrait')),
            ],
            selected: {f.orientation},
            onSelectionChanged: (s) =>
                n.set(f.copyWith(orientation: s.first)),
          ),
          _dropdown<int>(
            context,
            label: 'Min width',
            value: f.minWidth,
            items: const {
              0: 'Any',
              800: '800px',
              1200: '1200px',
              1600: '1600px',
              2400: '2400px',
            },
            onChanged: (v) => n.set(f.copyWith(minWidth: v)),
          ),
          _dropdown<String>(
            context,
            label: 'License',
            value: f.licenseContains ?? '',
            items: const {
              '': 'Any',
              'public domain': 'Public Domain',
              'cc0': 'CC0',
              'by': 'CC BY',
              'by-sa': 'CC BY-SA',
            },
            onChanged: (v) => n.set(v.isEmpty
                ? f.copyWith(clearLicense: true)
                : f.copyWith(licenseContains: v)),
          ),
          _dropdown<ImageSort>(
            context,
            label: 'Sort',
            value: f.sort,
            items: const {
              ImageSort.relevance: 'Best match',
              ImageSort.newest: 'Newest',
              ImageSort.popular: 'Most popular',
            },
            onChanged: (v) => n.set(f.copyWith(sort: v)),
          ),
          FilterChip(
            label: const Text('Photos only'),
            selected: f.photoOnly,
            onSelected: (v) => n.set(f.copyWith(photoOnly: v)),
          ),
          FilledButton.icon(
            onPressed: searching ? null : onSearch,
            icon: searching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search_rounded),
            label: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    BuildContext context, {
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        DropdownButton<T>(
          value: value,
          onChanged: (v) => v == null ? null : onChanged(v),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
        ),
      ],
    );
  }
}

// ── Result card ──────────────────────────────────────────────────────────────
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onTap});
  final ImageSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _thumb(result.thumbnailUrl),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _pill(context, result.source.label),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${result.resolutionLabel} · ${result.license ?? 'Unknown'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if ((result.photographer ?? '').isNotEmpty)
                    Text('© ${result.photographer}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _thumb(String url) => Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: const Color(0x22808080),
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
        loadingBuilder: (c, child, p) =>
            p == null ? child : const Center(child: CircularProgressIndicator()),
      );

  Widget _pill(BuildContext context, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 11)),
      );
}

// ── Preview + import dialog ──────────────────────────────────────────────────
class _PreviewDialog extends ConsumerStatefulWidget {
  const _PreviewDialog({
    required this.result,
    required this.destination,
    required this.onImported,
  });
  final ImageSearchResult result;
  final MasterLocation destination;
  final ValueChanged<String> onImported;

  @override
  ConsumerState<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends ConsumerState<_PreviewDialog> {
  bool _asHero = true;
  bool _busy = false;
  String? _error;

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(imageImportServiceProvider).import(
            widget.result,
            widget.destination,
            asHero: _asHero,
          );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onImported(res.rehosted
          ? 'Imported & re-hosted (${res.width}×${res.height}).'
          : 'Imported by reference (source blocked download; attribution saved).');
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                color: Colors.black,
                width: double.infinity,
                child: Image.network(r.imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Image.network(r.thumbnailUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: Colors.white54, size: 48)))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Wrap(spacing: 16, runSpacing: 4, children: [
                    _meta(context, Icons.aspect_ratio_rounded,
                        r.resolutionLabel),
                    _meta(context, Icons.copyright_rounded,
                        r.license ?? 'Unknown license'),
                    if ((r.photographer ?? '').isNotEmpty)
                      _meta(context, Icons.person_rounded, r.photographer!),
                    _meta(context, Icons.public_rounded, r.source.label),
                  ]),
                  if ((r.foreignLandingUrl ?? '').isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('View original source'),
                      onPressed: () =>
                          launchUrl(Uri.parse(r.foreignLandingUrl!)),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                          value: _asHero,
                          onChanged: (v) =>
                              setState(() => _asHero = v ?? true)),
                      const Text('Set as hero image'),
                      const Spacer(),
                      TextButton(
                          onPressed:
                              _busy ? null : () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _busy ? null : _import,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_rounded),
                        label: Text(_busy
                            ? 'Importing…'
                            : 'Import to ${widget.destination.name}'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(BuildContext context, IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Theme.of(context).disabledColor),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

// ── Existing Media Library tab ────────────────────────────────────────────────
class _MediaLibraryTab extends ConsumerStatefulWidget {
  const _MediaLibraryTab();
  @override
  ConsumerState<_MediaLibraryTab> createState() => _MediaLibraryTabState();
}

class _MediaLibraryTabState extends ConsumerState<_MediaLibraryTab> {
  String _q = '';
  bool _onlySelected = false;

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(mediaAssetsProvider);
    final selected = ref.watch(selectedMediaDestinationProvider);
    return assets.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (all) {
        final q = _q.toLowerCase();
        final images = all.where((a) {
          if (!a.isImage) return false;
          if (_onlySelected &&
              selected != null &&
              a.destinationId != selected.id) {
            return false;
          }
          if (q.isEmpty) return true;
          return (a.title ?? '').toLowerCase().contains(q) ||
              (a.photographer ?? '').toLowerCase().contains(q) ||
              (a.license ?? '').toLowerCase().contains(q) ||
              (a.recordType ?? '').toLowerCase().contains(q);
        }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText:
                          'Search by title, photographer, license, category…',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                const SizedBox(width: 12),
                if (selected != null)
                  FilterChip(
                    label: Text('Only ${selected.name}'),
                    selected: _onlySelected,
                    onSelected: (v) => setState(() => _onlySelected = v),
                  ),
              ]),
            ),
            Expanded(
              child: images.isEmpty
                  ? const Center(child: Text('No images in the library yet.'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(20),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 280,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: images.length,
                      itemBuilder: (_, i) =>
                          _LibraryCard(asset: images[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LibraryCard extends ConsumerWidget {
  const _LibraryCard({required this.asset});
  final MediaAsset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              _ResultCard._thumb(asset.thumbnail ?? asset.publicUrl ?? ''),
              if (asset.isHero)
                const Positioned(
                  top: 6,
                  left: 6,
                  child: Chip(
                      label: Text('HERO'),
                      visualDensity: VisualDensity.compact),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: PopupMenuButton<String>(
                  onSelected: (v) => _action(context, ref, v),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'hero',
                        enabled: !asset.isHero,
                        child: const Text('Set as hero')),
                    const PopupMenuItem(
                        value: 'gallery', child: Text('Move to gallery')),
                    const PopupMenuItem(
                        value: 'open', child: Text('Open original')),
                    const PopupMenuItem(
                        value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(asset.title ?? 'Untitled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                Text(
                    [asset.license ?? 'Unknown', asset.source ?? '']
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _action(
      BuildContext context, WidgetRef ref, String v) async {
    final repo = ref.read(mediaManagerRepositoryProvider);
    switch (v) {
      case 'hero':
        await repo.updateAsset(asset.id, {'is_hero': true});
        await _promoteHeroOnLocation(ref);
        ref.invalidate(mediaAssetsProvider);
      case 'gallery':
        await repo.updateAsset(asset.id, {'is_hero': false});
        ref.invalidate(mediaAssetsProvider);
      case 'open':
        final url = asset.publicUrl ?? asset.thumbnail;
        if (url != null) await launchUrl(Uri.parse(url));
      case 'delete':
        final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Delete image?'),
                content: const Text(
                    'This removes the media record. Storage files are left in place.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete')),
                ],
              ),
            ) ??
            false;
        if (ok) {
          await repo.deleteAsset(asset.id);
          ref.invalidate(mediaAssetsProvider);
        }
    }
  }

  /// When promoting to hero, move its URL to index 0 of the location's images.
  Future<void> _promoteHeroOnLocation(WidgetRef ref) async {
    final url = asset.publicUrl;
    final destId = asset.destinationId;
    if (url == null || destId == null) return;
    final all = ref.read(masterLocationsProvider).value ?? const [];
    MasterLocation? loc;
    for (final l in all) {
      if (l.id == destId) {
        loc = l;
        break;
      }
    }
    if (loc == null) return;
    final images = [...loc.images]..removeWhere((u) => u == url);
    images.insert(0, url);
    await ref.read(locationRepositoryProvider).update(loc.id, {'images': images});
    ref.read(locationRefreshProvider.notifier).bump();
  }
}

// ── Upload My Own tab ──────────────────────────────────────────────────────────
class _UploadTab extends ConsumerStatefulWidget {
  const _UploadTab();
  @override
  ConsumerState<_UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends ConsumerState<_UploadTab> {
  bool _busy = false;
  String? _note;

  Future<void> _pickAndUpload() async {
    final dest = ref.read(selectedMediaDestinationProvider);
    if (dest == null) {
      setState(() => _note = 'Pick a destination first.');
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    setState(() {
      _busy = true;
      _note = 'Uploading ${picked.files.length} file(s)…';
    });
    var ok = 0;
    var fail = 0;
    for (final f in picked.files) {
      final bytes = f.bytes;
      if (bytes == null) {
        fail++;
        continue;
      }
      try {
        await ref.read(imageImportServiceProvider).importBytes(
              bytes,
              f.name,
              dest,
              asHero: ok == 0 && dest.images.isEmpty,
            );
        ok++;
      } catch (_) {
        fail++;
      }
    }
    ref.read(locationRefreshProvider.notifier).bump();
    ref.invalidate(mediaAssetsProvider);
    if (mounted) {
      setState(() {
        _busy = false;
        _note = 'Uploaded $ok, failed $fail.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dest = ref.watch(selectedMediaDestinationProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_rounded,
                size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text('Upload your own photos',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              dest == null
                  ? 'Pick a destination, then upload one or more images.'
                  : 'They will be resized (hero/medium/thumbnail), stored, and '
                      'attached to ${dest.name}.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _pickAndUpload,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_rounded),
              label: Text(_busy ? 'Uploading…' : 'Choose images'),
            ),
            if (_note != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(_note!,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Recently Imported tab ──────────────────────────────────────────────────────
class _RecentlyImportedTab extends ConsumerWidget {
  const _RecentlyImportedTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(mediaAssetsProvider);
    return assets.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (all) {
        final images = all.where((a) => a.isImage).toList()
          ..sort((a, b) => (b.createdAt ?? DateTime(0))
              .compareTo(a.createdAt ?? DateTime(0)));
        final recent = images.take(60).toList();
        if (recent.isEmpty) {
          return const Center(child: Text('Nothing imported yet.'));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 280,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.82,
          ),
          itemCount: recent.length,
          itemBuilder: (_, i) => _LibraryCard(asset: recent[i]),
        );
      },
    );
  }
}
