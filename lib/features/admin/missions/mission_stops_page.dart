import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import 'package:explorer_os_mobile/features/admin/missions/mission_stop_detail_page.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/admin/widgets/map_location_picker.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_stop.dart';

/// Admin -> one mission's stop list: ADD STOP, then drill into each stop for
/// its travel/approach/arrival content, QR portal, and Old World.
class MissionStopsPage extends ConsumerWidget {
  const MissionStopsPage({super.key, required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stopsAsync = ref.watch(missionStopsProvider(mission.id));
    return Scaffold(
      appBar: AppBar(title: Text(mission.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showStopEditorDialog(context, ref, mission, stopsAsync.value ?? const []),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add Stop'),
      ),
      body: stopsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmptyState(message: 'Could not load stops: $e'),
        data: (stops) => stops.isEmpty
            ? const AdminEmptyState(
                message: 'No stops yet. Add the first one.', icon: Icons.pin_drop_outlined)
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final s in stops) ...[
                    AdminSectionCard(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${s.sequence}')),
                        title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${s.latitude.toStringAsFixed(5)}, ${s.longitude.toStringAsFixed(5)} · '
                            '${s.arrivalRadiusMeters.round()}m radius'
                            '${s.requiresQr ? ' · QR required' : ''}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: 'Edit stop',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                showStopEditorDialog(context, ref, mission, stops, stop: s),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'delete') {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Delete stop?'),
                                    content: Text(
                                        'This deletes "${s.title}" and its travel stories. This cannot be undone.'),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Cancel')),
                                      FilledButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Delete')),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  await ref.read(missionRepositoryProvider).deleteStop(s.id);
                                  ref.read(missionsRefreshProvider.notifier).bump();
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'delete', child: Text('Delete stop')),
                            ],
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ]),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MissionStopDetailPage(mission: mission, stop: s),
                        )),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
      ),
    );
  }
}

/// The stop create/edit dialog. Used for both "Add Stop" (no [stop]) and
/// "Edit stop". GPS coordinates are picked visually via the shared map
/// picker rather than typed as raw numbers.
Future<void> showStopEditorDialog(
  BuildContext context,
  WidgetRef ref,
  Mission mission,
  List<MissionStop> existingStops, {
  MissionStop? stop,
}) async {
  final title = TextEditingController(text: stop?.title ?? '');
  final radius = TextEditingController(text: '${stop?.arrivalRadiusMeters ?? 150}');
  var picked = stop != null ? LatLng(stop.latitude, stop.longitude) : null;
  var requiresQr = stop?.requiresQr ?? true;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(stop == null ? 'Add stop' : 'Edit stop'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final result = await showMapLocationPicker(
                  context,
                  initial: picked,
                  title: stop == null ? 'Place this stop' : 'Move ${stop.title}',
                );
                if (result != null) setState(() => picked = result);
              },
              icon: const Icon(Icons.map_rounded),
              label: Text(picked == null
                  ? 'Pick location on map'
                  : '${picked!.latitude.toStringAsFixed(5)}, ${picked!.longitude.toStringAsFixed(5)}'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: radius,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Arrival radius (meters)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Requires QR scan'),
              value: requiresQr,
              onChanged: (v) => setState(() => requiresQr = v),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: picked == null ? null : () => Navigator.pop(dialogContext, true),
              child: Text(stop == null ? 'Add' : 'Save')),
        ],
      ),
    ),
  );

  if (saved != true || title.text.trim().isEmpty || picked == null) return;
  final repo = ref.read(missionRepositoryProvider);
  final row = {
    'title': title.text.trim(),
    'latitude': picked!.latitude,
    'longitude': picked!.longitude,
    'arrival_radius_meters': double.tryParse(radius.text.trim()) ?? 150,
    'requires_qr': requiresQr,
  };
  if (stop == null) {
    final nextSequence = existingStops.isEmpty
        ? 1
        : existingStops.map((s) => s.sequence).reduce((a, b) => a > b ? a : b) + 1;
    await repo.createStop({...row, 'mission_id': mission.id, 'sequence': nextSequence});
  } else {
    await repo.updateStop(stop.id, row);
  }
  ref.read(missionsRefreshProvider.notifier).bump();
}
