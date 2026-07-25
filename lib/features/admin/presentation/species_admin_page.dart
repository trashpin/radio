import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/image_match/filename_normalizer.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/discovery_category.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';

/// Admin → Species: create/edit species and upload their photo directly to
/// Supabase (replaces the Base44 workflow). Requires a signed-in admin
/// (writes are RLS-gated to `authenticated`) and the `species_images` bucket.
class SpeciesAdminPage extends ConsumerStatefulWidget {
  const SpeciesAdminPage({super.key});
  @override
  ConsumerState<SpeciesAdminPage> createState() => _SpeciesAdminPageState();
}

class _SpeciesAdminPageState extends ConsumerState<SpeciesAdminPage> {
  String _query = '';
  String _catFilter = 'all';

  static const _destinationId = '8338b34e-4d8f-4ff8-a8a3-13b7d82feba2'; // Ocala

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(allSpeciesProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Species',
          subtitle: 'Create, edit, and photograph species — saved to Supabase',
          actions: [
            FilledButton.icon(
              onPressed: () => _openEditor(null),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add species'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search species…',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          const Gap.h(AppSpacing.md),
          DropdownButton<String>(
            value: _catFilter,
            onChanged: (v) => setState(() => _catFilter = v ?? 'all'),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('All categories')),
              for (final c in discoveryCategories)
                DropdownMenuItem(value: c.token, child: Text(c.label)),
            ],
          ),
        ]),
        const Gap.v(AppSpacing.md),
        async.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Could not load species.\n$e')),
          data: (all) {
            final rows = all.where((s) {
              if (_catFilter != 'all' && s.category != _catFilter) return false;
              if (_query.isEmpty) return true;
              return s.commonName.toLowerCase().contains(_query);
            }).toList();
            if (rows.isEmpty) {
              return const AdminSectionCard(
                  child: AdminEmptyState(
                      message: 'No species. Click "Add species" to create one.',
                      icon: Icons.eco_rounded));
            }
            return AdminSectionCard(
              child: Column(children: [
                for (final s in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: (s.heroImageUrl != null)
                          ? Image.network(s.heroImageUrl!,
                              width: 48, height: 48, fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) =>
                                  const Icon(Icons.image_not_supported_rounded))
                          : Container(
                              width: 48,
                              height: 48,
                              color: theme.dividerColor.withValues(alpha: 0.3),
                              child: const Icon(Icons.eco_rounded)),
                    ),
                    title: Text(s.commonName,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      s.category,
                      if (s.scientificName != null) s.scientificName,
                      if (s.heroImageUrl == null) 'no image',
                    ].whereType<String>().join('  ·  ')),
                    trailing: TextButton(
                        onPressed: () => _openEditor(s),
                        child: const Text('Edit')),
                  ),
              ]),
            );
          },
        ),
      ],
    );
  }

  Future<void> _openEditor(Species? existing) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SpeciesEditorDialog(
          existing: existing, destinationId: _destinationId),
    );
    if (saved == true) ref.invalidate(allSpeciesProvider);
  }
}

class _SpeciesEditorDialog extends ConsumerStatefulWidget {
  const _SpeciesEditorDialog({this.existing, required this.destinationId});
  final Species? existing;
  final String destinationId;
  @override
  ConsumerState<_SpeciesEditorDialog> createState() =>
      _SpeciesEditorDialogState();
}

class _SpeciesEditorDialogState extends ConsumerState<_SpeciesEditorDialog> {
  late final _name = TextEditingController(text: widget.existing?.commonName);
  late final _sci = TextEditingController(text: widget.existing?.scientificName);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late final _facts = TextEditingController(text: widget.existing?.funFacts);
  late String _category = widget.existing?.category ?? 'animals';
  late final String? _heroImage = widget.existing?.heroImage;
  Uint8List? _pickedBytes;
  String? _pickedName;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _sci.dispose();
    _desc.dispose();
    _facts.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    setState(() {
      _pickedBytes = f.bytes;
      _pickedName = f.name;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Common name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(speciesRepositoryProvider);
      var heroImage = _heroImage;

      // Upload the picked image to storage (requires signed-in admin).
      if (_pickedBytes != null) {
        final ext = (_pickedName ?? 'jpg').split('.').last.toLowerCase();
        final key = normalizeMatchKey(_name.text);
        final path = '$_category/$key.$ext';
        final storage = SupabaseService.client.storage.from('species_images');
        await storage.uploadBinary(path, _pickedBytes!,
            fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'));
        heroImage = storage.getPublicUrl(path);
      }

      final species = Species(
        id: widget.existing?.id ?? '',
        category: _category,
        commonName: _name.text.trim(),
        scientificName: _sci.text.trim().isEmpty ? null : _sci.text.trim(),
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        funFacts: _facts.text.trim().isEmpty ? null : _facts.text.trim(),
        heroImage: heroImage,
        destinationId: widget.existing?.destinationId ?? widget.destinationId,
        published: true,
      );
      await repo.upsert(species);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Save failed (are you signed in + migration 0010 run?): $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _pickedBytes != null
        ? Image.memory(_pickedBytes!, height: 120, fit: BoxFit.cover)
        : (_heroImage != null
            ? Image.network(_heroImage, height: 120, fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => const SizedBox())
            : null);
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add species' : 'Edit species'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(
                  labelText: 'Category', border: OutlineInputBorder()),
              items: [
                for (final c in discoveryCategories)
                  DropdownMenuItem(value: c.token, child: Text(c.label)),
              ],
              onChanged: (v) => setState(() => _category = v ?? 'animals'),
            ),
            const Gap.v(AppSpacing.md),
            _field(_name, 'Common name *'),
            const Gap.v(AppSpacing.md),
            _field(_sci, 'Scientific name'),
            const Gap.v(AppSpacing.md),
            _field(_desc, 'Description', lines: 3),
            const Gap.v(AppSpacing.md),
            _field(_facts, 'Fun facts', lines: 2),
            const Gap.v(AppSpacing.md),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_rounded, size: 18),
                label: Text(_pickedBytes != null || _heroImage != null
                    ? 'Change photo'
                    : 'Upload photo'),
              ),
              const Gap.h(AppSpacing.md),
              if (preview != null)
                ClipRRect(
                    borderRadius: BorderRadius.circular(8), child: preview),
            ]),
            if (_error != null) ...[
              const Gap.v(AppSpacing.md),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, {int lines = 1}) =>
      TextField(
        controller: c,
        maxLines: lines,
        decoration:
            InputDecoration(labelText: label, border: const OutlineInputBorder()),
      );
}
