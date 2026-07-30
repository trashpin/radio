import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/admin/media_manager/data/media_manager_repository.dart';
import 'package:explorer_os_mobile/features/admin/media_search/data/image_import_service.dart';
import 'package:explorer_os_mobile/features/admin/media_search/data/image_search_service.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/image_filters.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/search_query.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Opens the per-location "Find & Save Photo" dialog: search Wikimedia /
/// Openverse for THIS location, pick the image you want, and save it as the
/// hero (or add it to the gallery) — all from the location itself.
///
/// Returns `true` if at least one image was saved (so the caller can refresh).
Future<bool> showLocationImagePicker(
    BuildContext context, MasterLocation location) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _LocationImagePickerDialog(location: location),
  );
  return changed ?? false;
}

class _LocationImagePickerDialog extends ConsumerStatefulWidget {
  const _LocationImagePickerDialog({required this.location});
  final MasterLocation location;
  @override
  ConsumerState<_LocationImagePickerDialog> createState() =>
      _LocationImagePickerDialogState();
}

class _LocationImagePickerDialogState
    extends ConsumerState<_LocationImagePickerDialog> {
  late MasterLocation _location = widget.location;
  late final TextEditingController _query = TextEditingController(
    text: buildPrimaryQuery(SearchDestination(
      name: widget.location.name,
      county: widget.location.county,
      typeLabel: widget.location.type.label,
    )),
  );
  ImageSource _source = ImageSource.wikimedia;
  bool _loading = false;
  bool _changed = false;
  String? _error;
  String? _busyId; // result currently importing
  List<ImageSearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref
          .read(imageSearchServiceProvider)
          .searchQuery(_source, _query.text.trim());
      const filters = ImageFilters(minWidth: 1000); // slightly relaxed floor
      setState(() {
        _results = filters.apply(raw, destinationName: _location.name);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _import(ImageSearchResult r, {required bool asHero}) async {
    setState(() => _busyId = r.id);
    try {
      final res = await ref
          .read(imageImportServiceProvider)
          .import(r, _location, asHero: asHero, minWidth: 1000);
      // Reflect the new image locally so a follow-up import stacks correctly.
      final imgs = [..._location.images]..remove(res.heroUrl);
      if (asHero) {
        imgs.insert(0, res.heroUrl);
      } else {
        imgs.add(res.heroUrl);
      }
      _location = _location.copyWith(images: imgs);
      _changed = true;
      ref.read(locationRefreshProvider.notifier).bump();
      ref.invalidate(mediaAssetsProvider);
      if (mounted) {
        _snack(asHero
            ? 'Saved as hero for ${_location.name}'
                '${res.rehosted ? '' : ' (referenced source)'}.'
            : 'Added to ${_location.name} gallery.');
      }
    } catch (e) {
      if (mounted) _snack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _uploadOwn() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    setState(() => _busyId = '__upload__');
    var ok = 0;
    for (final f in picked.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      try {
        final res = await ref.read(imageImportServiceProvider).importBytes(
              bytes,
              f.name,
              _location,
              asHero: _location.images.isEmpty && ok == 0,
            );
        final imgs = [..._location.images]..remove(res.heroUrl);
        if (_location.images.isEmpty && ok == 0) {
          imgs.insert(0, res.heroUrl);
        } else {
          imgs.add(res.heroUrl);
        }
        _location = _location.copyWith(images: imgs);
        ok++;
      } catch (_) {}
    }
    _changed = _changed || ok > 0;
    ref.read(locationRefreshProvider.notifier).bump();
    ref.invalidate(mediaAssetsProvider);
    if (mounted) {
      setState(() => _busyId = null);
      _snack('Uploaded $ok photo(s) to ${_location.name}.');
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hero = _location.images.isEmpty ? null : _location.images.first;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Icon(Icons.image_search_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Find & save a photo',
                          style: theme.textTheme.titleLarge),
                      Text(
                          '${_location.name}'
                          '${_location.county == null ? '' : ' · ${_location.county} County'}'
                          '  ·  ${_location.images.length} photo(s)',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (hero != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _NetImg(hero, width: 64, height: 48),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context, _changed),
                ),
              ]),
              const SizedBox(height: 12),
              // Controls
              Row(children: [
                SegmentedButton<ImageSource>(
                  segments: const [
                    ButtonSegment(
                        value: ImageSource.wikimedia,
                        label: Text('Wikimedia')),
                    ButtonSegment(
                        value: ImageSource.openverse,
                        label: Text('Openverse')),
                  ],
                  selected: {_source},
                  onSelectionChanged: (s) {
                    setState(() => _source = s.first);
                    _search();
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _query,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                      hintText: 'Search query',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _loading ? null : _search,
                    child: const Text('Search')),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busyId == '__upload__' ? null : _uploadOwn,
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: const Text('Upload'),
                ),
              ]),
              const SizedBox(height: 12),
              Expanded(child: _body(theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text('Search failed: $_error'));
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('No images found. Try editing the search query above.',
            style: theme.textTheme.bodyMedium),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.74,
      ),
      itemCount: _results.length,
      itemBuilder: (_, i) => _card(_results[i], theme),
    );
  }

  Widget _card(ImageSearchResult r, ThemeData theme) {
    final busy = _busyId == r.id;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              _NetImg(r.thumbnailUrl),
              if ((r.foreignLandingUrl ?? '').isNotEmpty)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: IconButton(
                      iconSize: 16,
                      color: Colors.white,
                      icon: const Icon(Icons.open_in_new_rounded),
                      tooltip: 'View source',
                      onPressed: () => launchUrl(Uri.parse(r.foreignLandingUrl!)),
                    ),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text('${r.resolutionLabel} · ${r.license ?? 'Unknown'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Row(children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 34)),
                    onPressed: _busyId != null
                        ? null
                        : () => _import(r, asHero: true),
                    child: const Text('Set hero',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Add to gallery',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
                  onPressed: _busyId != null
                      ? null
                      : () => _import(r, asHero: false),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Network image that never shows a broken-image glyph.
class _NetImg extends StatelessWidget {
  const _NetImg(this.url, {this.width, this.height});
  final String url;
  final double? width;
  final double? height;
  @override
  Widget build(BuildContext context) => Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: width,
          height: height,
          color: const Color(0x22808080),
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
        loadingBuilder: (c, child, p) => p == null
            ? child
            : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
}
