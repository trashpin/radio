import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/species_images/wildlife_placeholder.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/nearby_gems/data/nearby_gems_repository.dart';
import 'package:explorer_os_mobile/features/nearby_gems/models/nearby_gem.dart';

/// Admin → Nearby Gems Manager. The ONLY source of Nearby Gems shown to users:
/// an admin adds/approves every gem here. No Google Places / third-party import.
class NearbyGemsManagerPage extends ConsumerWidget {
  const NearbyGemsManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(allNearbyGemsProvider);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('New Gem'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (gems) {
          final active = gems.where((g) => g.active).length;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Nearby Gems Manager', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                  'The only source of Nearby Gems. Users see ACTIVE gems within '
                  'range — nothing is imported from Google Places or elsewhere.',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(spacing: 12, children: [
                Chip(label: Text('$active active')),
                Chip(label: Text('${gems.length - active} inactive')),
                Chip(label: Text('${gems.length} total')),
              ]),
              const SizedBox(height: 16),
              if (gems.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(children: [
                    const Icon(Icons.diamond_outlined, size: 44),
                    const SizedBox(height: 8),
                    const Text('No gems yet.'),
                    const SizedBox(height: 4),
                    Text(
                        'Tap "New Gem" to add one. (Run migration 0034 first if '
                        'you see a load error.)',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall),
                  ]),
                )
              else
                for (final g in gems) _row(context, ref, g),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, NearbyGem g) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: SizedBox(
          width: 56,
          height: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SpeciesImageOrPlaceholder(
                url: g.featuredImage, category: g.category, compact: true),
          ),
        ),
        title: Row(children: [
          Flexible(child: Text(g.name, overflow: TextOverflow.ellipsis)),
          if (!g.active) ...[
            const SizedBox(width: 8),
            Chip(
                label: const Text('Inactive'),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.errorContainer),
          ],
        ]),
        subtitle: Text([
          if ((g.category ?? '').isNotEmpty) g.category,
          if ((g.badge ?? '').isNotEmpty) g.badge,
          if (g.hasStory) 'has story',
        ].whereType<String>().join(' · ')),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            final repo = ref.read(nearbyGemsRepositoryProvider);
            switch (v) {
              case 'edit':
                _openEditor(context, ref, gem: g);
              case 'toggle':
                await repo.update(g.id, {'active': !g.active});
                ref.read(nearbyGemsRefreshProvider.notifier).bump();
              case 'delete':
                await repo.delete(g.id);
                ref.read(nearbyGemsRefreshProvider.notifier).bump();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
                value: 'toggle',
                child: Text(g.active ? 'Set inactive' : 'Set active')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => _openEditor(context, ref, gem: g),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      {NearbyGem? gem}) async {
    final saved = await showDialog<bool>(
        context: context, builder: (_) => _GemEditor(gem: gem));
    if (saved == true) ref.read(nearbyGemsRefreshProvider.notifier).bump();
  }
}

class _GemEditor extends ConsumerStatefulWidget {
  const _GemEditor({this.gem});
  final NearbyGem? gem;
  @override
  ConsumerState<_GemEditor> createState() => _GemEditorState();
}

class _GemEditorState extends ConsumerState<_GemEditor> {
  late final _name = TextEditingController(text: widget.gem?.name ?? '');
  late final _address = TextEditingController(text: widget.gem?.address ?? '');
  late final _website = TextEditingController(text: widget.gem?.website ?? '');
  late final _phone = TextEditingController(text: widget.gem?.phone ?? '');
  late final _lat =
      TextEditingController(text: widget.gem?.latitude?.toString() ?? '');
  late final _lng =
      TextEditingController(text: widget.gem?.longitude?.toString() ?? '');
  late final _short =
      TextEditingController(text: widget.gem?.shortDescription ?? '');
  late final _long = TextEditingController(text: widget.gem?.longStory ?? '');
  late final _narration =
      TextEditingController(text: widget.gem?.narrationUrl ?? '');
  late String? _category = widget.gem?.category;
  late String? _badge = widget.gem?.badge;
  late String? _featured = widget.gem?.featuredImage;
  late final List<String> _gallery = [...?widget.gem?.galleryImages];
  late bool _active = widget.gem?.active ?? true;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _website, _phone, _lat, _lng, _short,
        _long, _narration]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage({required bool featured}) async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final url = await ref.read(nearbyGemsRepositoryProvider).uploadImage(
          res.files.first.bytes!, res.files.first.name);
      setState(() => featured ? _featured = url : _gallery.add(url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image uploaded — press Save to keep it.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pull a picture + GPS (and, when blank, name/category/description) from an
  /// existing ExplorerOS master location — so gems reuse curated content.
  Future<void> _matchLocation() async {
    // Await the data — masterLocationsProvider is async and is often not loaded
    // yet on first open, which previously showed an empty "No matches" picker.
    setState(() => _busy = true);
    List<MasterLocation> all;
    try {
      all = await ref.read(masterLocationsProvider.future);
    } catch (_) {
      all = ref.read(masterLocationsProvider).value ?? const [];
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final loc = await showDialog<MasterLocation>(
      context: context,
      builder: (_) => _LocationPicker(all: all),
    );
    if (loc == null) return;
    setState(() {
      if ((_featured ?? '').isEmpty && loc.images.isNotEmpty) {
        _featured = loc.images.first;
      }
      for (final u in loc.images) {
        if (u != _featured && !_gallery.contains(u)) _gallery.add(u);
      }
      if (loc.latitude != null) _lat.text = loc.latitude.toString();
      if (loc.longitude != null) _lng.text = loc.longitude.toString();
      if (_name.text.trim().isEmpty) _name.text = loc.name;
      if ((_short.text.trim().isEmpty) && (loc.description ?? '').isNotEmpty) {
        _short.text = loc.description!;
      }
      _category ??= _gemCategoryFor(loc.type);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Matched to ${loc.name}')));
    }
  }

  static String? _gemCategoryFor(LocationType t) {
    switch (t) {
      case LocationType.restaurant:
        return 'Restaurant';
      case LocationType.museum:
      case LocationType.historicSite:
      case LocationType.historicDistrict:
        return 'Museum';
      case LocationType.statePark:
      case LocationType.nationalPark:
      case LocationType.countyPark:
      case LocationType.forest:
      case LocationType.trail:
      case LocationType.trailhead:
      case LocationType.spring:
      case LocationType.lake:
      case LocationType.river:
        return 'Outdoors';
      default:
        return 'Attraction';
    }
  }

  Future<void> _pickAudio() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.audio, withData: true);
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final url = await ref.read(nearbyGemsRepositoryProvider).uploadImage(
          res.files.first.bytes!, res.files.first.name,
          contentType: 'audio/mpeg');
      setState(() => _narration.text = url);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name is required.')));
      return;
    }
    setState(() => _busy = true);
    final row = <String, dynamic>{
      'name': _name.text.trim(),
      'category': _category,
      'badge': _badge,
      'featured_image': _featured,
      'gallery_images': _gallery,
      'latitude': double.tryParse(_lat.text.trim()),
      'longitude': double.tryParse(_lng.text.trim()),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'website': _website.text.trim().isEmpty ? null : _website.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'narration_url':
          _narration.text.trim().isEmpty ? null : _narration.text.trim(),
      'short_description':
          _short.text.trim().isEmpty ? null : _short.text.trim(),
      'long_story': _long.text.trim().isEmpty ? null : _long.text.trim(),
      'active': _active,
    };
    try {
      final repo = ref.read(nearbyGemsRepositoryProvider);
      if (widget.gem == null) {
        await repo.create(row);
      } else {
        await repo.update(widget.gem!.id, row);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.gem == null ? 'New Gem' : 'Edit Gem'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Featured image — tap the image itself to upload (unmissable).
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _busy ? null : () => _pickImage(featured: true),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SpeciesImageOrPlaceholder(
                          url: _featured,
                          category: _category,
                          label: _name.text),
                      if ((_featured ?? '').isEmpty)
                        const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_rounded,
                                  color: Colors.white, size: 30),
                              SizedBox(height: 6),
                              Text('Tap to add a photo',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pickImage(featured: true),
                icon: const Icon(Icons.image_rounded, size: 18),
                label: const Text('Featured image'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pickImage(featured: false),
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                label: Text('Gallery (${_gallery.length})'),
              ),
            ]),
            const SizedBox(height: 8),
            // Reuse an existing ExplorerOS location's photo + coordinates
            // instead of uploading from scratch.
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _matchLocation,
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Match to an ExplorerOS location'),
              ),
            ),
            const Divider(height: 24),
            _f(_name, 'Name *'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _dropdown('Category', NearbyGem.categoryOptions,
                  _category, (v) => setState(() => _category = v))),
              const SizedBox(width: 8),
              Expanded(child: _dropdown('ExplorerOS Badge',
                  NearbyGem.badgeOptions, _badge, (v) => setState(() => _badge = v))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _f(_lat, 'Latitude')),
              const SizedBox(width: 8),
              Expanded(child: _f(_lng, 'Longitude')),
            ]),
            const SizedBox(height: 8),
            _f(_address, 'Address'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _f(_website, 'Website')),
              const SizedBox(width: 8),
              Expanded(child: _f(_phone, 'Phone')),
            ]),
            const SizedBox(height: 8),
            _f(_short, 'Short description', maxLines: 2),
            const SizedBox(height: 8),
            _f(_long, 'Long story', maxLines: 4),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _f(_narration, 'AI narration audio URL')),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickAudio,
                icon: const Icon(Icons.audiotrack_rounded, size: 18),
                label: const Text('Upload'),
              ),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Active (visible to users)'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(widget.gem == null ? 'Create' : 'Save')),
      ],
    );
  }

  Widget _f(TextEditingController c, String label, {int maxLines = 1}) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder()),
      );

  Widget _dropdown(String label, List<String> options, String? value,
          ValueChanged<String?> onChanged) =>
      DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder()),
        items: [
          const DropdownMenuItem(value: null, child: Text('—')),
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: onChanged,
      );
}

/// A searchable picker over the master `locations` list — used to match a gem
/// to an existing ExplorerOS location (and reuse its photo + coordinates).
class _LocationPicker extends StatefulWidget {
  const _LocationPicker({required this.all});
  final List<MasterLocation> all;
  @override
  State<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<_LocationPicker> {
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
      title: const Text('Match to a location'),
      content: SizedBox(
        width: 460,
        height: 480,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search locations by name or county…',
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
                      final hero = l.images.isNotEmpty ? l.images.first : null;
                      return ListTile(
                        leading: SizedBox(
                          width: 44,
                          height: 44,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SpeciesImageOrPlaceholder(
                                url: hero, category: l.type.label, compact: true),
                          ),
                        ),
                        title: Text(l.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          l.type.label,
                          if (l.county != null) '${l.county} County',
                          '${l.images.length} photo(s)',
                        ].join(' · ')),
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
            child: const Text('Close')),
      ],
    );
  }
}
