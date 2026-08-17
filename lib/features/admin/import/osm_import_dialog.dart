import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/import/location_import_service.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';

/// Admin dialog: import real locations from OpenStreetMap for an area (a
/// bounding box around a chosen center + radius). Dedupes on (source,
/// source_id) so re-running updates existing rows instead of duplicating.
Future<void> showOsmImportDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _OsmImportDialog());

class _OsmImportDialog extends ConsumerStatefulWidget {
  const _OsmImportDialog();
  @override
  ConsumerState<_OsmImportDialog> createState() => _OsmImportDialogState();
}

class _OsmImportDialogState extends ConsumerState<_OsmImportDialog> {
  late final _lat = TextEditingController();
  late final _lng = TextEditingController();
  late final _state = TextEditingController();
  late final _county = TextEditingController();
  double _radiusMiles = 3;
  bool _onlyMissing = false;
  bool _running = false;
  final _log = <String>[];
  ImportSummary? _result;

  @override
  void initState() {
    super.initState();
    // Prefill from the current map/GPS center when available.
    final c = ref.read(mapCenterProvider);
    if (c != null) {
      _lat.text = c.latitude.toStringAsFixed(5);
      _lng.text = c.longitude.toStringAsFixed(5);
    }
  }

  @override
  void dispose() {
    for (final c in [_lat, _lng, _state, _county]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat == null || lng == null) {
      setState(() => _log.add('Enter a valid latitude and longitude.'));
      return;
    }
    setState(() {
      _running = true;
      _result = null;
      _log.clear();
    });
    final r = _radiusMiles * 1609.344;
    final dLat = r / 111320.0;
    final dLng = r / (111320.0 * math.cos(lat * math.pi / 180).abs());
    final summary =
        await ref.read(locationImportServiceProvider).importOsmBoundingBox(
              south: lat - dLat,
              north: lat + dLat,
              west: lng - dLng,
              east: lng + dLng,
              state: _state.text.trim().isEmpty ? null : _state.text.trim(),
              county: _county.text.trim().isEmpty ? null : _county.text.trim(),
              onlyMissing: _onlyMissing,
              onLog: (m) => setState(() => _log.add(m)),
            );
    if (!mounted) return;
    setState(() {
      _running = false;
      _result = summary;
    });
    ref.read(locationRefreshProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import from OpenStreetMap'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Imports parks, museums, historic sites, springs, restaurants, '
                'towns and more within the chosen radius. Existing rows are '
                'updated (deduped by source), never duplicated.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _f(_lat, 'Center latitude')),
              const SizedBox(width: 8),
              Expanded(child: _f(_lng, 'Center longitude')),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _f(_state, 'State (optional)')),
              const SizedBox(width: 8),
              Expanded(child: _f(_county, 'County (optional)')),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Text('Radius: '),
              Expanded(
                child: Slider(
                  value: _radiusMiles,
                  min: 1,
                  max: 15,
                  divisions: 14,
                  label: '${_radiusMiles.round()} mi',
                  onChanged: _running
                      ? null
                      : (v) => setState(() => _radiusMiles = v),
                ),
              ),
              Text('${_radiusMiles.round()} mi'),
            ]),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _onlyMissing,
              onChanged: _running
                  ? null
                  : (v) => setState(() => _onlyMissing = v ?? false),
              title: const Text('Only import missing (skip existing)'),
            ),
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_log.join('\n'),
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Imported ${_result!.inserted} · updated ${_result!.updated}'
                  ' · skipped ${_result!.skipped}'
                  '${_result!.failed > 0 ? ' · failed ${_result!.failed}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
            if (_running) const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context),
          child: Text(_result != null ? 'Close' : 'Cancel'),
        ),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Import'),
        ),
      ],
    );
  }

  Widget _f(TextEditingController c, String label) => TextField(
        controller: c,
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
      );
}
