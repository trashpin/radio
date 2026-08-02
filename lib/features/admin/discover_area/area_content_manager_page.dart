import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/data/area_content_repository.dart';
import 'package:explorer_os_mobile/features/discover_area/models/area_content_block.dart';
import 'package:explorer_os_mobile/features/discover_area/models/area_discovery_category.dart';

/// Admin → (opened from a Master Locations "Area" row) → Discovery Content
/// Manager. Every narrated block for this area, across every category —
/// add/edit/delete/reorder. `area_discovery_content` (migration 0042) is
/// generic, so adding a brand-new category here works the moment it exists
/// in [areaDiscoveryCategories] (or, later, in Category Manager) — no schema
/// change needed.
class AreaContentManagerPage extends ConsumerWidget {
  const AreaContentManagerPage({
    super.key,
    required this.locationId,
    required this.areaName,
  });

  final String locationId;
  final String areaName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(areaContentForLocationProvider(locationId));
    return Scaffold(
      appBar: AppBar(title: Text('Discovery Content — $areaName')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Block'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (blocks) {
          if (blocks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 44),
                    const SizedBox(height: 8),
                    const Text('No content blocks yet.'),
                    const SizedBox(height: 4),
                    Text(
                      'Add one for History, Nature, Geology, or any other '
                      'category — travelers will hear it in order.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          }
          final byCategory = <String, List<AreaContentBlock>>{};
          for (final b in blocks) {
            (byCategory[b.categoryToken] ??= []).add(b);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final entry in byCategory.entries) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_labelFor(entry.key),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                for (final b in entry.value) _row(context, ref, b),
              ],
            ],
          );
        },
      ),
    );
  }

  String _labelFor(String token) {
    for (final c in areaDiscoveryCategories) {
      if (c.token == token) return c.label;
    }
    return token;
  }

  Widget _row(BuildContext context, WidgetRef ref, AreaContentBlock b) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${b.sortOrder}')),
        title: Row(
          children: [
            Flexible(child: Text(b.title, overflow: TextOverflow.ellipsis)),
            if (!b.active) ...[
              const SizedBox(width: 8),
              const Chip(
                label: Text('Inactive'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        subtitle: Text(b.hasNarration ? 'Has narration' : 'Needs narration'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            final repo = ref.read(areaContentRepositoryProvider);
            switch (v) {
              case 'edit':
                _openEditor(context, ref, block: b);
              case 'toggle':
                await repo.update(b.id, {'active': !b.active});
                ref.read(areaContentRefreshProvider.notifier).bump();
              case 'delete':
                await repo.delete(b.id);
                ref.read(areaContentRefreshProvider.notifier).bump();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(b.active ? 'Set inactive' : 'Set active'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => _openEditor(context, ref, block: b),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    AreaContentBlock? block,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BlockEditor(locationId: locationId, block: block),
    );
    if (saved == true) ref.read(areaContentRefreshProvider.notifier).bump();
  }
}

class _BlockEditor extends ConsumerStatefulWidget {
  const _BlockEditor({required this.locationId, this.block});
  final String locationId;
  final AreaContentBlock? block;
  @override
  ConsumerState<_BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends ConsumerState<_BlockEditor> {
  late String _category =
      widget.block?.categoryToken ?? areaDiscoveryCategories.first.token;
  late final _title = TextEditingController(text: widget.block?.title ?? '');
  late final _script =
      TextEditingController(text: widget.block?.narrationScript ?? '');
  late final _audioUrl = TextEditingController(text: widget.block?.audioUrl ?? '');
  late final _images =
      TextEditingController(text: (widget.block?.images ?? const []).join(', '));
  late final _sortOrder =
      TextEditingController(text: '${widget.block?.sortOrder ?? 0}');
  late bool _active = widget.block?.active ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _script, _audioUrl, _images, _sortOrder]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Title is required.')));
      return;
    }
    setState(() => _saving = true);
    final row = {
      'location_id': widget.locationId,
      'category_token': _category,
      'title': title,
      'narration_script': _script.text.trim().isEmpty ? null : _script.text.trim(),
      'audio_url': _audioUrl.text.trim().isEmpty ? null : _audioUrl.text.trim(),
      'images': _images.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      'sort_order': int.tryParse(_sortOrder.text.trim()) ?? 0,
      'active': _active,
    };
    try {
      final repo = ref.read(areaContentRepositoryProvider);
      if (widget.block == null) {
        await repo.create(row);
      } else {
        await repo.update(widget.block!.id, row);
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
      title: Text(widget.block == null ? 'New content block' : 'Edit block'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in areaDiscoveryCategories)
                    DropdownMenuItem(value: c.token, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Title (e.g. "Early Settlement")',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _script,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Narration script (spoken via TTS if no audio URL)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _audioUrl,
                decoration: const InputDecoration(
                  labelText: 'Recorded audio URL (optional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _images,
                decoration: const InputDecoration(
                  labelText: 'Image URLs (comma-separated)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sortOrder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Play order (lower plays first)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
