import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/admin/categories/category_image_import_service.dart';
import 'package:explorer_os_mobile/features/admin/media_search/data/image_search_service.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/image_filters.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/search_query.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';
import 'package:explorer_os_mobile/shared/design/category_fallback_image_repository.dart';

/// Opens the "Find & save a category photo" dialog — the same Wikimedia/
/// Openverse search + open-license import pipeline the Media Search Center
/// already uses for locations and events, applied to a Discover category
/// bucket's fallback photograph instead. [categoryLabel] is only used to
/// build a sensible default search query; [categoryKey] is the canonical
/// bucket key ([categoryVisualKeyFor]) actually written to
/// `category_fallback_images`. Returns `true` if a photo was saved.
Future<bool> showCategoryImagePicker(
  BuildContext context, {
  required String categoryKey,
  required String categoryLabel,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _CategoryImagePickerDialog(
      categoryKey: categoryKey,
      categoryLabel: categoryLabel,
    ),
  );
  return changed ?? false;
}

class _CategoryImagePickerDialog extends ConsumerStatefulWidget {
  const _CategoryImagePickerDialog({
    required this.categoryKey,
    required this.categoryLabel,
  });
  final String categoryKey;
  final String categoryLabel;
  @override
  ConsumerState<_CategoryImagePickerDialog> createState() =>
      _CategoryImagePickerDialogState();
}

class _CategoryImagePickerDialogState extends ConsumerState<_CategoryImagePickerDialog> {
  late final TextEditingController _query = TextEditingController(
    text: buildPrimaryQuery(SearchDestination(
      name: '${widget.categoryLabel} Marion County Florida',
    )),
  );
  ImageSource _source = ImageSource.wikimedia;
  bool _loading = false;
  bool _changed = false;
  String? _error;
  String? _busyId;
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
      final raw =
          await ref.read(imageSearchServiceProvider).searchQuery(_source, _query.text.trim());
      const filters = ImageFilters(minWidth: 800);
      setState(() {
        _results = filters.apply(raw, destinationName: widget.categoryLabel);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _import(ImageSearchResult r) async {
    setState(() => _busyId = r.id);
    try {
      await ref
          .read(categoryImageImportServiceProvider)
          .import(r, widget.categoryKey, minWidth: 800);
      _changed = true;
      ref.read(categoryFallbackImagesRefreshProvider.notifier).bump();
      if (mounted) _snack('Saved as the photo for ${widget.categoryLabel}.');
    } catch (e) {
      if (mounted) _snack('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.image_search_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Find & save a category photo', style: theme.textTheme.titleLarge),
                      Text(widget.categoryLabel, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context, _changed),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                SegmentedButton<ImageSource>(
                  segments: const [
                    ButtonSegment(value: ImageSource.wikimedia, label: Text('Wikimedia')),
                    ButtonSegment(value: ImageSource.openverse, label: Text('Openverse')),
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
                FilledButton(onPressed: _loading ? null : _search, child: const Text('Search')),
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
    if (_error != null) return Center(child: Text('Search failed: $_error'));
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
        childAspectRatio: 0.82,
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
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
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
              child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 34)),
                  onPressed: _busyId != null ? null : () => _import(r),
                  child: const Text('Use this photo', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NetImg extends StatelessWidget {
  const _NetImg(this.url);
  final String url;
  @override
  Widget build(BuildContext context) => Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: const Color(0x22808080),
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
        loadingBuilder: (c, child, p) =>
            p == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
}
