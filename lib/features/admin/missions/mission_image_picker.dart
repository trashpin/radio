import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/admin/media_search/data/image_search_service.dart';
import 'package:explorer_os_mobile/features/admin/media_search/logic/image_filters.dart';
import 'package:explorer_os_mobile/features/admin/media_search/models/image_search_result.dart';
import 'package:explorer_os_mobile/features/admin/missions/mission_image_import_service.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';

/// Opens a "Find & save an introduction image" dialog for a mission's
/// Adventure Card / Mission Introduction artwork — the SAME Wikimedia/
/// Openverse search + open-license import pipeline the Media Search Center
/// already uses for locations and events (see event_image_picker.dart),
/// applied to `missions.hero_image_url` instead. Deliberately does NOT seed
/// the search query from the mission's own title/description the way the
/// event picker does — that would surface real photos of the destination,
/// exactly what this image must NOT be (spec: "the image should represent
/// the mystery," never the location). Returns `true` if an image was saved.
Future<bool> showMissionImagePicker(BuildContext context, Mission mission) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _MissionImagePickerDialog(mission: mission),
  );
  return changed ?? false;
}

class _MissionImagePickerDialog extends ConsumerStatefulWidget {
  const _MissionImagePickerDialog({required this.mission});
  final Mission mission;
  @override
  ConsumerState<_MissionImagePickerDialog> createState() => _MissionImagePickerDialogState();
}

class _MissionImagePickerDialogState extends ConsumerState<_MissionImagePickerDialog> {
  final TextEditingController _query = TextEditingController();
  ImageSource _source = ImageSource.wikimedia;
  bool _loading = false;
  bool _changed = false;
  String? _error;
  String? _busyId;
  List<ImageSearchResult> _results = const [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_query.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw =
          await ref.read(imageSearchServiceProvider).searchQuery(_source, _query.text.trim());
      const filters = ImageFilters(minWidth: 1000);
      setState(() {
        _results = filters.apply(raw, destinationName: _query.text.trim());
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
      await ref.read(missionImageImportServiceProvider).import(r, widget.mission);
      _changed = true;
      ref.read(missionsRefreshProvider.notifier).bump();
      if (mounted) _snack('Saved as the introduction image for ${widget.mission.title}.');
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
                Icon(Icons.auto_awesome_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Find an introduction image', style: theme.textTheme.titleLarge),
                      Text(widget.mission.title, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context, _changed),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                'This is mystery artwork, not a photo of the destination — search for a symbolic '
                'object instead (lantern, old journal, compass, key, symbol...). It may be worth '
                'searching for the same object a later story step references, so the player has '
                'an "I saw that before" moment.',
                style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
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
                    autofocus: true,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                      hintText: 'e.g. "antique lantern", "old leather journal"',
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
        child: Text(
            _query.text.trim().isEmpty
                ? 'Search for a symbolic object above to get started.'
                : 'No images found. Try a different search.',
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
                  child: const Text('Use this image', style: TextStyle(fontSize: 12)),
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
