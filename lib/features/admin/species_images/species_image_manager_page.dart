import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/species_images/species_image_repository.dart';
import 'package:explorer_os_mobile/features/admin/species_images/wildlife_placeholder.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';

/// Admin → Species Image Manager. Audit which species need photos, then search
/// a species and upload / replace / delete / approve / reorder its gallery and
/// choose the featured image — with a live card preview. The `media` table
/// (species_id) is the master image library; `species.hero_image` is the
/// featured pick. Nothing else (UI/GPS/radio/narration/park) is touched.
class SpeciesImageManagerPage extends StatelessWidget {
  const SpeciesImageManagerPage({super.key});

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
              tabs: [
                Tab(icon: Icon(Icons.fact_check_rounded), text: 'Image Audit'),
                Tab(icon: Icon(Icons.photo_library_rounded), text: 'Manage'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [_AuditTab(), _ManageTab()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The species the Manage tab is editing (shared so Audit can jump to it).
final _selectedSpeciesProvider =
    NotifierProvider<_SelectedSpecies, Species?>(_SelectedSpecies.new);

class _SelectedSpecies extends Notifier<Species?> {
  @override
  Species? build() => null;
  void select(Species? s) => state = s;
}

/// Which tab index is showing (so Audit → Manage can switch).
final _tabIndexProvider = NotifierProvider<_TabIndex, int>(_TabIndex.new);

class _TabIndex extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

// ── Phase 3: Image Audit ─────────────────────────────────────────────────────
class _AuditTab extends ConsumerStatefulWidget {
  const _AuditTab();
  @override
  ConsumerState<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends ConsumerState<_AuditTab> {
  String _q = '';
  bool _needsOnly = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(speciesImageAuditProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (rows) {
        final total = rows.length;
        final withImg = rows.where((r) => r.hasFeatured).length;
        final needs = rows.where((r) => r.needsImage).length;
        final q = _q.toLowerCase();
        final filtered = rows.where((r) {
          if (_needsOnly && !r.needsImage) return false;
          if (q.isEmpty) return true;
          return r.species.commonName.toLowerCase().contains(q) ||
              (r.species.scientificName ?? '').toLowerCase().contains(q);
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                _stat(context, '$total', 'Species'),
                const SizedBox(width: 12),
                _stat(context, '$withImg', 'Has image',
                    tint: const Color(0xFF2E7D32)),
                const SizedBox(width: 12),
                _stat(context, '$needs', 'Needs image',
                    tint: theme.colorScheme.error),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search species…',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Needs image only'),
                  selected: _needsOnly,
                  onSelected: (v) => setState(() => _needsOnly = v),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = filtered[i];
                  return ListTile(
                    leading: SizedBox(
                      width: 44,
                      height: 44,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SpeciesImageOrPlaceholder(
                          url: r.species.heroImageUrl,
                          category: r.species.category,
                          compact: true,
                        ),
                      ),
                    ),
                    title: Text(r.species.commonName),
                    subtitle: Text([
                      if ((r.species.scientificName ?? '').isNotEmpty)
                        r.species.scientificName!,
                      '${r.galleryCount} in gallery',
                    ].join(' · '),
                        style: theme.textTheme.bodySmall),
                    trailing: r.needsImage
                        ? Chip(
                            label: const Text('Needs image'),
                            backgroundColor:
                                theme.colorScheme.errorContainer,
                            visualDensity: VisualDensity.compact)
                        : const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF2E7D32)),
                    onTap: () {
                      ref
                          .read(_selectedSpeciesProvider.notifier)
                          .select(r.species);
                      ref.read(_tabIndexProvider.notifier).set(1);
                      DefaultTabController.of(context).animateTo(1);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _stat(BuildContext context, String value, String label, {Color? tint}) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(value,
              style: theme.textTheme.headlineSmall?.copyWith(
                  color: tint, fontWeight: FontWeight.bold)),
          Text(label, style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

// ── Phase 5/6: Manage ────────────────────────────────────────────────────────
class _ManageTab extends ConsumerWidget {
  const _ManageTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(_selectedSpeciesProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 280, child: _SpeciesPicker(selected: selected)),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const Center(child: Text('Select a species to manage its photos.'))
              : _SpeciesPanel(species: selected),
        ),
      ],
    );
  }
}

class _SpeciesPicker extends ConsumerStatefulWidget {
  const _SpeciesPicker({this.selected});
  final Species? selected;
  @override
  ConsumerState<_SpeciesPicker> createState() => _SpeciesPickerState();
}

class _SpeciesPickerState extends ConsumerState<_SpeciesPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allSpeciesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search species…',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (species) {
              final q = _q.toLowerCase();
              final list = species
                  .where((s) =>
                      q.isEmpty ||
                      s.commonName.toLowerCase().contains(q) ||
                      (s.scientificName ?? '').toLowerCase().contains(q))
                  .toList()
                ..sort((a, b) => a.commonName
                    .toLowerCase()
                    .compareTo(b.commonName.toLowerCase()));
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  final sel = s.id == widget.selected?.id;
                  return ListTile(
                    dense: true,
                    selected: sel,
                    leading: Icon(
                      (s.heroImageUrl ?? '').isNotEmpty
                          ? Icons.image_rounded
                          : Icons.hide_image_outlined,
                      color: (s.heroImageUrl ?? '').isNotEmpty
                          ? const Color(0xFF2E7D32)
                          : Theme.of(context).colorScheme.error,
                      size: 20,
                    ),
                    title: Text(s.commonName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () =>
                        ref.read(_selectedSpeciesProvider.notifier).select(s),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SpeciesPanel extends ConsumerStatefulWidget {
  const _SpeciesPanel({required this.species});
  final Species species;
  @override
  ConsumerState<_SpeciesPanel> createState() => _SpeciesPanelState();
}

class _SpeciesPanelState extends ConsumerState<_SpeciesPanel> {
  bool _busy = false;

  SpeciesImageRepository get _repo =>
      ref.read(speciesImageRepositoryProvider);

  Future<void> _run(Future<void> Function() op) async {
    setState(() => _busy = true);
    try {
      await op();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      ref.read(speciesImageRefreshProvider.notifier).bump();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.image, allowMultiple: true, withData: true);
    if (picked == null || picked.files.isEmpty) return;
    await _run(() async {
      for (final f in picked.files) {
        if (f.bytes == null) continue;
        await _repo.upload(
            species: widget.species, bytes: f.bytes!, filename: f.name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.species;
    final theme = Theme.of(context);
    final imagesAsync = ref.watch(speciesImagesProvider(s.id));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.commonName, style: theme.textTheme.headlineSmall),
                if ((s.scientificName ?? '').isNotEmpty)
                  Text(s.scientificName!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontStyle: FontStyle.italic)),
                Text(s.category, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _upload,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_rounded),
            label: const Text('Upload photos'),
          ),
        ]),
        const SizedBox(height: 20),
        // Card preview (how the species card looks).
        Text('Card preview', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _CardPreview(species: s),
        const SizedBox(height: 24),
        Text('Gallery', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        imagesAsync.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('$e'),
          data: (images) => images.isEmpty
              ? _emptyGallery(theme)
              : Column(
                  children: [
                    for (var i = 0; i < images.length; i++)
                      _galleryRow(images, i),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _emptyGallery(ThemeData theme) => Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Center(
          child: Text('No photos yet — upload one above.',
              style: theme.textTheme.bodyMedium),
        ),
      );

  Widget _galleryRow(List<SpeciesImage> images, int i) {
    final img = images[i];
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 84,
              height: 84,
              child: SpeciesImageOrPlaceholder(
                  url: img.url, category: widget.species.category),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (img.isFeatured)
                    const Chip(
                        label: Text('FEATURED'),
                        visualDensity: VisualDensity.compact),
                  if (!img.approved)
                    Chip(
                        label: const Text('Pending'),
                        backgroundColor: theme.colorScheme.errorContainer,
                        visualDensity: VisualDensity.compact),
                ]),
                Text([img.photographer, img.license]
                        .whereType<String>()
                        .where((x) => x.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          // Reorder
          IconButton(
            tooltip: 'Move up',
            icon: const Icon(Icons.arrow_upward_rounded),
            onPressed: (_busy || i == 0)
                ? null
                : () => _run(() {
                      final list = [...images];
                      final t = list.removeAt(i);
                      list.insert(i - 1, t);
                      return _repo.reorder(list);
                    }),
          ),
          IconButton(
            tooltip: 'Move down',
            icon: const Icon(Icons.arrow_downward_rounded),
            onPressed: (_busy || i == images.length - 1)
                ? null
                : () => _run(() {
                      final list = [...images];
                      final t = list.removeAt(i);
                      list.insert(i + 1, t);
                      return _repo.reorder(list);
                    }),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'feature':
                  _run(() => _repo.setFeatured(widget.species.id, img));
                case 'approve':
                  _run(() => _repo.setApproved(img, !img.approved));
                case 'delete':
                  _run(() => _repo.delete(widget.species.id, img));
              }
            },
            itemBuilder: (_) => [
              if (!img.isFeatured)
                const PopupMenuItem(
                    value: 'feature', child: Text('Set as featured')),
              PopupMenuItem(
                  value: 'approve',
                  child: Text(img.approved ? 'Unapprove' : 'Approve')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
      ),
    );
  }
}

/// A live preview of how the species card renders (image + name + category).
class _CardPreview extends StatelessWidget {
  const _CardPreview({required this.species});
  final Species species;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 240,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 140,
              width: double.infinity,
              child: SpeciesImageOrPlaceholder(
                url: species.heroImageUrl,
                category: species.category,
                label: species.commonName,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(species.commonName,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if ((species.scientificName ?? '').isNotEmpty)
                    Text(species.scientificName!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
