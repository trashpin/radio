import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/data/geofence_repository.dart';
import 'package:explorer_os_mobile/features/gps/models/geofence.dart';
import 'package:explorer_os_mobile/features/gps/models/geofence_level.dart';

/// Admin → (opened from a Master Locations row) → Geofence Manager.
/// Circle-only, form-based — the polygon map-drawing editor is a later
/// phase (see the architecture doc). This is enough to build and test the
/// hierarchy: level, parent, center point, radius, priority override.
class GeofenceManagerPage extends ConsumerWidget {
  const GeofenceManagerPage({
    super.key,
    required this.locationId,
    required this.locationName,
    required this.defaultLat,
    required this.defaultLng,
  });

  final String locationId;
  final String locationName;
  final double? defaultLat;
  final double? defaultLng;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(geofencesForLocationProvider(locationId));
    final allGeofences = ref.watch(geofencesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text('Geofences — $locationName')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, allGeofences),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add Geofence'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (geofences) {
          if (geofences.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.public_off_rounded, size: 44),
                    const SizedBox(height: 8),
                    const Text('No geofence for this location yet.'),
                    const SizedBox(height: 4),
                    Text(
                      'Add one to place it in the hierarchy — e.g. mark it '
                      'as a Park, then a POI inside that park references '
                      'the Park as its parent.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final g in geofences) _row(context, ref, g, allGeofences),
            ],
          );
        },
      ),
    );
  }

  String _parentLabel(Geofence g, List<Geofence> all) {
    if (g.parentId == null) return 'No parent (top-level)';
    for (final p in all) {
      if (p.id == g.parentId) return '${p.level.label}: ${p.locationId}';
    }
    return 'Parent (not found)';
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    Geofence g,
    List<Geofence> all,
  ) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${g.effectivePriority}')),
        title: Row(
          children: [
            Text(g.level.label, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (!g.active) ...[
              const SizedBox(width: 8),
              const Chip(
                label: Text('Inactive'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${g.radiusMeters.round()}m radius · ${_parentLabel(g, all)}\n'
          '${g.centerLat.toStringAsFixed(5)}, ${g.centerLng.toStringAsFixed(5)}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            final repo = ref.read(geofenceRepositoryProvider);
            switch (v) {
              case 'edit':
                _openEditor(context, ref, all, geofence: g);
              case 'toggle':
                await repo.update(g.id, {'active': !g.active});
                ref.read(geofenceRefreshProvider.notifier).bump();
              case 'delete':
                await repo.delete(g.id);
                ref.read(geofenceRefreshProvider.notifier).bump();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(g.active ? 'Set inactive' : 'Set active'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => _openEditor(context, ref, all, geofence: g),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    List<Geofence> allGeofences, {
    Geofence? geofence,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _GeofenceEditor(
        locationId: locationId,
        defaultLat: defaultLat,
        defaultLng: defaultLng,
        allGeofences: allGeofences,
        geofence: geofence,
      ),
    );
    if (saved == true) ref.read(geofenceRefreshProvider.notifier).bump();
  }
}

class _GeofenceEditor extends ConsumerStatefulWidget {
  const _GeofenceEditor({
    required this.locationId,
    required this.defaultLat,
    required this.defaultLng,
    required this.allGeofences,
    this.geofence,
  });
  final String locationId;
  final double? defaultLat;
  final double? defaultLng;
  final List<Geofence> allGeofences;
  final Geofence? geofence;

  @override
  ConsumerState<_GeofenceEditor> createState() => _GeofenceEditorState();
}

class _GeofenceEditorState extends ConsumerState<_GeofenceEditor> {
  late GeofenceLevel _level = widget.geofence?.level ?? GeofenceLevel.poi;
  late String? _parentId = widget.geofence?.parentId;
  late final _lat = TextEditingController(
    text: '${widget.geofence?.centerLat ?? widget.defaultLat ?? ''}',
  );
  late final _lng = TextEditingController(
    text: '${widget.geofence?.centerLng ?? widget.defaultLng ?? ''}',
  );
  late final _radius =
      TextEditingController(text: '${widget.geofence?.radiusMeters ?? 500}');
  late final _priorityOverride = TextEditingController(
    text: widget.geofence?.priorityOverride?.toString() ?? '',
  );
  late bool _active = widget.geofence?.active ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_lat, _lng, _radius, _priorityOverride]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    final radius = double.tryParse(_radius.text.trim());
    if (lat == null || lng == null || radius == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Latitude, longitude, and radius are required.')));
      return;
    }
    setState(() => _saving = true);
    final row = {
      'location_id': widget.locationId,
      'level': _level.id,
      'parent_id': _parentId,
      'center_lat': lat,
      'center_lng': lng,
      'radius_meters': radius,
      'priority_override': int.tryParse(_priorityOverride.text.trim()),
      'active': _active,
    };
    try {
      final repo = ref.read(geofenceRepositoryProvider);
      if (widget.geofence == null) {
        await repo.create(row);
      } else {
        await repo.update(widget.geofence!.id, row);
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
    final parentOptions = widget.allGeofences
        .where((g) => g.id != widget.geofence?.id)
        .toList();

    return AlertDialog(
      title: Text(widget.geofence == null ? 'New geofence' : 'Edit geofence'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<GeofenceLevel>(
                initialValue: _level,
                decoration: const InputDecoration(
                  labelText: 'Level',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final l in GeofenceLevel.values)
                    DropdownMenuItem(
                      value: l,
                      child: Text('${l.label} (priority ${l.defaultPriority})'),
                    ),
                ],
                onChanged: (v) => setState(() => _level = v ?? _level),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _parentId,
                decoration: const InputDecoration(
                  labelText: 'Parent geofence (optional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None (top-level)')),
                  for (final g in parentOptions)
                    DropdownMenuItem(
                      value: g.id,
                      child: Text('${g.level.label}: ${g.locationId}'),
                    ),
                ],
                onChanged: (v) => setState(() => _parentId = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      decoration: const InputDecoration(
                        labelText: 'Center latitude',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      decoration: const InputDecoration(
                        labelText: 'Center longitude',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _radius,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Radius (meters)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priorityOverride,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText:
                      'Priority override (optional — default for ${_level.label} is ${_level.defaultPriority})',
                  isDense: true,
                  border: const OutlineInputBorder(),
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
