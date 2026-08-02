import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/categories/category_repository.dart';
import 'package:explorer_os_mobile/features/admin/categories/location_category.dart';

/// Admin → Category Manager. Every category a location can be assigned —
/// seeded (migration 0039) with the app's built-in taxonomy, plus whatever
/// custom categories an admin adds here. `locations.category` has always
/// been free text, so adding a row here immediately makes it assignable in
/// the Master Locations editor — no code change needed.
class CategoryManagerPage extends ConsumerWidget {
  const CategoryManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(allCategoriesProvider);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.new_label_rounded),
        label: const Text('New Category'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (categories) {
          final active = categories.where((c) => c.active).length;
          final sorted = [...categories]
            ..sort((a, b) {
              final bySort = a.sortOrder.compareTo(b.sortOrder);
              return bySort != 0 ? bySort : a.label.compareTo(b.label);
            });
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Category Manager', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Every category a location can use. Add a new one here and it '
                'becomes assignable in Master Locations immediately — no app '
                'update required.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  Chip(label: Text('$active active')),
                  Chip(label: Text('${categories.length - active} inactive')),
                  Chip(label: Text('${categories.length} total')),
                ],
              ),
              const SizedBox(height: 16),
              if (categories.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.category_outlined, size: 44),
                      const SizedBox(height: 8),
                      const Text('No categories yet.'),
                      const SizedBox(height: 4),
                      Text(
                        'Run migration 0039 to seed the built-in taxonomy, or '
                        'tap "New Category" to add one.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              else
                for (final c in sorted) _row(context, ref, c),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, LocationCategory c) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            _iconFor(c.icon) ?? Icons.label_outline_rounded,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(c.label, overflow: TextOverflow.ellipsis)),
            if (!c.active) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('Inactive'),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.errorContainer,
              ),
            ],
          ],
        ),
        subtitle: Text('slug: ${c.slug} · sort ${c.sortOrder}'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            final repo = ref.read(categoryRepositoryProvider);
            switch (v) {
              case 'edit':
                _openEditor(context, ref, category: c);
              case 'toggle':
                await repo.update(c.id, {'active': !c.active});
                ref.read(categoryRefreshProvider.notifier).bump();
              case 'delete':
                await repo.delete(c.id);
                ref.read(categoryRefreshProvider.notifier).bump();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(c.active ? 'Set inactive' : 'Set active'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => _openEditor(context, ref, category: c),
      ),
    );
  }

  IconData? _iconFor(String? name) {
    // Small, deliberately limited set — enough to recognize a category at a
    // glance without pulling in a full icon-name registry.
    switch (name) {
      case 'park':
        return Icons.forest_rounded;
      case 'water':
        return Icons.water_rounded;
      case 'museum':
        return Icons.museum_rounded;
      case 'trail':
        return Icons.hiking_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'history':
        return Icons.account_balance_rounded;
      default:
        return null;
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    LocationCategory? category,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryEditor(category: category),
    );
    if (saved == true) ref.read(categoryRefreshProvider.notifier).bump();
  }
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({this.category});
  final LocationCategory? category;
  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final _slug = TextEditingController(text: widget.category?.slug ?? '');
  late final _label = TextEditingController(text: widget.category?.label ?? '');
  late final _icon = TextEditingController(text: widget.category?.icon ?? '');
  late final _sortOrder = TextEditingController(
    text: '${widget.category?.sortOrder ?? 0}',
  );
  late bool _active = widget.category?.active ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_slug, _label, _icon, _sortOrder]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final slug = _slug.text.trim();
    final label = _label.text.trim();
    if (slug.isEmpty || label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Slug and label are required.')),
      );
      return;
    }
    setState(() => _saving = true);
    final row = {
      'slug': slug,
      'label': label,
      'icon': _icon.text.trim().isEmpty ? null : _icon.text.trim(),
      'sort_order': int.tryParse(_sortOrder.text.trim()) ?? 0,
      'active': _active,
    };
    try {
      final repo = ref.read(categoryRepositoryProvider);
      if (widget.category == null) {
        await repo.create(row);
      } else {
        await repo.update(widget.category!.id, row);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.category == null ? 'New category' : 'Edit category'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _slug,
                decoration: const InputDecoration(
                  labelText: 'Slug (stored value, e.g. "brewery")',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Label (shown in the admin/pickers)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _icon,
                decoration: const InputDecoration(
                  labelText: 'Icon key (optional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sortOrder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sort order',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text('Only active categories appear in pickers'),
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
