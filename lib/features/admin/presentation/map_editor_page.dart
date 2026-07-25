import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/maps/data/admin_map_repository.dart';
import 'package:explorer_os_mobile/features/maps/models/map_poi.dart';

/// Category styling: label, marker/circle color, marker hue, default radius (m).
class _Cat {
  const _Cat(this.label, this.color, this.hue, this.radius);
  final String label;
  final Color color;
  final double hue;
  final int radius;
}

const _cats = <String, _Cat>{
  'trailheads': _Cat('Trailheads', Color(0xFF43A047), BitmapDescriptor.hueGreen, 91),
  'visitor_centers':
      _Cat('Visitor Centers', Color(0xFF1E88E5), BitmapDescriptor.hueAzure, 100),
  'historic_sites':
      _Cat('Historic Sites', Color(0xFF8E24AA), BitmapDescriptor.hueViolet, 152),
  'wildlife_viewing':
      _Cat('Wildlife Viewing', Color(0xFFFDD835), BitmapDescriptor.hueYellow, 61),
  'safety_alerts':
      _Cat('Safety Alerts', Color(0xFFE53935), BitmapDescriptor.hueRed, 150),
  'campgrounds':
      _Cat('Campgrounds', Color(0xFFFB8C00), BitmapDescriptor.hueOrange, 120),
  'parking': _Cat('Parking', Color(0xFF90A4AE), BitmapDescriptor.hueCyan, 60),
  'springs': _Cat('Springs', Color(0xFF00ACC1), BitmapDescriptor.hueCyan, 120),
  'scenic_overlooks':
      _Cat('Scenic Overlooks', Color(0xFF2E7D32), BitmapDescriptor.hueGreen, 122),
  'poi': _Cat('Other', Color(0xFF9E9E9E), BitmapDescriptor.hueRose, 100),
};
_Cat _catOf(String c) => _cats[c] ?? _cats['poi']!;

/// Admin → Map Editor: a GIS-style editor to view/drag/add/edit POIs on a map.
class MapEditorPage extends ConsumerStatefulWidget {
  const MapEditorPage({super.key});
  @override
  ConsumerState<MapEditorPage> createState() => _MapEditorPageState();
}

class _MapEditorPageState extends ConsumerState<MapEditorPage> {
  final List<MapPoi> _pois = [];
  bool _seeded = false;
  GoogleMapController? _map;
  MapPoi? _selected;
  final Set<String> _filter = {};
  bool _addMode = false;
  final _searchCtrl = TextEditingController();

  static const _ocala = LatLng(29.18, -81.71);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int _radiusOf(MapPoi p) => p.triggerRadiusM ?? _catOf(p.category).radius;

  List<MapPoi> get _visible => _filter.isEmpty
      ? _pois
      : _pois.where((p) => _filter.contains(p.category)).toList();

  Future<void> _persist(MapPoi p, {bool delete = false}) async {
    final repo = ref.read(adminMapRepositoryProvider);
    try {
      if (delete) {
        await repo.delete(p.id);
      } else {
        final saved = await repo.upsert(p);
        final i = _pois.indexWhere((x) => x.id == p.id);
        if (i >= 0) setState(() => _pois[i] = saved);
        if (_selected?.id == p.id) setState(() => _selected = saved);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Saved locally (run migration 0009 to persist): $e'),
            duration: const Duration(seconds: 2)));
      }
    }
  }

  void _move(MapPoi p, LatLng to) {
    final i = _pois.indexWhere((x) => x.id == p.id);
    if (i < 0) return;
    final updated = _pois[i].copyWith(latitude: to.latitude, longitude: to.longitude);
    setState(() {
      _pois[i] = updated;
      if (_selected?.id == p.id) _selected = updated;
    });
    _persist(updated); // save the new position
  }

  void _addAt(LatLng at) {
    final poi = MapPoi(
      id: '', // new
      name: 'New POI',
      category: 'poi',
      latitude: at.latitude,
      longitude: at.longitude,
      parkCode: 'ocala',
    );
    setState(() {
      _pois.add(poi);
      _selected = poi;
      _addMode = false;
    });
  }

  void _duplicate(MapPoi p) {
    final copy = MapPoi(
      id: '',
      name: '${p.name} (copy)',
      category: p.category,
      latitude: p.latitude + 0.002,
      longitude: p.longitude + 0.002,
      description: p.description,
      triggerRadiusM: p.triggerRadiusM,
      parkCode: p.parkCode,
      destinationId: p.destinationId,
    );
    setState(() {
      _pois.add(copy);
      _selected = copy;
    });
  }

  void _search() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return;
    final hit = _pois.where((p) => p.name.toLowerCase().contains(q)).toList();
    if (hit.isEmpty) return;
    final p = hit.first;
    _map?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(p.latitude, p.longitude), 13));
    setState(() => _selected = p);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(mapEditorPoisProvider);
    if (!_seeded && async.hasValue) {
      _seeded = true;
      _pois.addAll(async.value!);
    }

    final markers = <Marker>{
      for (final p in _visible)
        Marker(
          markerId: MarkerId(p.id.isEmpty ? 'new_${p.name}' : p.id),
          position: LatLng(p.latitude, p.longitude),
          draggable: true,
          onDragEnd: (pos) => _move(p, pos),
          icon: BitmapDescriptor.defaultMarkerWithHue(_catOf(p.category).hue),
          onTap: () => setState(() => _selected = p),
        ),
    };
    final circles = <Circle>{
      for (final p in _visible)
        Circle(
          circleId: CircleId('r_${p.id.isEmpty ? p.name : p.id}'),
          center: LatLng(p.latitude, p.longitude),
          radius: _radiusOf(p).toDouble(),
          strokeColor: _catOf(p.category).color,
          strokeWidth: 2,
          fillColor: _catOf(p.category).color.withValues(alpha: 0.12),
        ),
    };

    return Column(children: [
      _toolbar(async),
      Expanded(
        child: Row(children: [
          Expanded(
            child: Stack(children: [
              GoogleMap(
                initialCameraPosition:
                    const CameraPosition(target: _ocala, zoom: 10),
                markers: markers,
                circles: circles,
                mapType: MapType.hybrid,
                zoomControlsEnabled: false,
                onMapCreated: (c) => _map = c,
                onTap: _addMode ? _addAt : null,
              ),
              if (_addMode)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    color: Colors.black87,
                    child: const Text('Add POI mode — tap the map to place',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              Positioned(bottom: 12, left: 12, child: _legend()),
            ]),
          ),
          if (_selected != null)
            _EditPanel(
              key: ValueKey(_selected!.id.isEmpty
                  ? 'new_${_selected!.name}'
                  : _selected!.id),
              poi: _selected!,
              radius: _radiusOf(_selected!),
              onClose: () => setState(() => _selected = null),
              onSave: (p) {
                final i = _pois.indexWhere((x) =>
                    x.id == _selected!.id && x.name == _selected!.name);
                setState(() {
                  if (i >= 0) _pois[i] = p;
                  _selected = p;
                });
                _persist(p);
              },
              onDelete: () {
                final target = _selected!;
                setState(() {
                  _pois.removeWhere((x) =>
                      x.id == target.id && x.name == target.name);
                  _selected = null;
                });
                if (target.id.isNotEmpty) _persist(target, delete: true);
              },
              onDuplicate: () => _duplicate(_selected!),
            ),
        ]),
      ),
    ]);
  }

  Widget _toolbar(AsyncValue async) {
    return Material(
      color: Theme.of(context).cardColor,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(children: [
          Row(children: [
            Text('Map Editor',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const Gap.h(AppSpacing.lg),
            Text('${_pois.length} POIs',
                style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            SizedBox(
              width: 240,
              child: TextField(
                controller: _searchCtrl,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search POI…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      onPressed: _search),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const Gap.h(AppSpacing.md),
            FilledButton.icon(
              onPressed: () => setState(() => _addMode = !_addMode),
              style: FilledButton.styleFrom(
                  backgroundColor: _addMode ? Colors.red : null,
                  minimumSize: const Size(0, 40)),
              icon: Icon(_addMode ? Icons.close_rounded : Icons.add_location_alt_rounded,
                  size: 18),
              label: Text(_addMode ? 'Cancel' : 'Add POI'),
            ),
          ]),
          const Gap.v(AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 6, children: [
              for (final e in _cats.entries)
                FilterChip(
                  label: Text(e.value.label),
                  selected: _filter.contains(e.key),
                  avatar: CircleAvatar(
                      backgroundColor: e.value.color, radius: 7),
                  onSelected: (s) => setState(() =>
                      s ? _filter.add(e.key) : _filter.remove(e.key)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _legend() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in _cats.entries)
            Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(backgroundColor: e.value.color, radius: 5),
              const SizedBox(width: 6),
              Text(e.value.label,
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ]),
        ],
      ),
    );
  }
}

class _EditPanel extends StatefulWidget {
  const _EditPanel({
    super.key,
    required this.poi,
    required this.radius,
    required this.onClose,
    required this.onSave,
    required this.onDelete,
    required this.onDuplicate,
  });
  final MapPoi poi;
  final int radius;
  final VoidCallback onClose;
  final void Function(MapPoi) onSave;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;

  @override
  State<_EditPanel> createState() => _EditPanelState();
}

class _EditPanelState extends State<_EditPanel> {
  late final TextEditingController _name =
      TextEditingController(text: widget.poi.name);
  late final TextEditingController _desc =
      TextEditingController(text: widget.poi.description ?? '');
  late String _category = widget.poi.category;
  late double _radius = widget.radius.toDouble();

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 340,
      color: theme.cardColor,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(children: [
            Expanded(
                child: Text('Edit POI',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700))),
            IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded)),
          ]),
          const Gap.v(AppSpacing.sm),
          TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Name', border: OutlineInputBorder())),
          const Gap.v(AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _cats.containsKey(_category) ? _category : 'poi',
            decoration: const InputDecoration(
                labelText: 'Category', border: OutlineInputBorder()),
            items: [
              for (final e in _cats.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value.label)),
            ],
            onChanged: (v) => setState(() => _category = v ?? 'poi'),
          ),
          const Gap.v(AppSpacing.md),
          Row(children: [
            Expanded(
                child: Text('Lat: ${widget.poi.latitude.toStringAsFixed(5)}',
                    style: theme.textTheme.bodySmall)),
            Expanded(
                child: Text('Lng: ${widget.poi.longitude.toStringAsFixed(5)}',
                    style: theme.textTheme.bodySmall)),
          ]),
          const Text('Drag the marker on the map to move it.',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const Gap.v(AppSpacing.md),
          TextField(
              controller: _desc,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Description', border: OutlineInputBorder())),
          const Gap.v(AppSpacing.md),
          Text('GPS trigger radius: ${_radius.round()} m '
              '(${(_radius * 3.281).round()} ft)'),
          Slider(
            value: _radius.clamp(20, 400),
            min: 20,
            max: 400,
            divisions: 38,
            label: '${_radius.round()} m',
            onChanged: (v) => setState(() => _radius = v),
          ),
          const Gap.v(AppSpacing.md),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => widget.onSave(widget.poi.copyWith(
                    name: _name.text.trim(),
                    category: _category,
                    description: _desc.text.trim(),
                    triggerRadiusM: _radius.round())),
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save'),
              ),
            ),
            const Gap.h(AppSpacing.sm),
            IconButton(
                tooltip: 'Duplicate',
                onPressed: widget.onDuplicate,
                icon: const Icon(Icons.copy_rounded)),
            IconButton(
                tooltip: 'Delete',
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Colors.red)),
          ]),
          const Gap.v(AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Preview in App — opens this POI in the app'))),
            icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
            label: const Text('Preview in App'),
          ),
        ],
      ),
    );
  }
}
