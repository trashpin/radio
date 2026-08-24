import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/missions/mission_stop_detail_page.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
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
        onPressed: () => _addStop(context, ref, stopsAsync.value ?? const []),
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
                        trailing: const Icon(Icons.chevron_right_rounded),
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

  Future<void> _addStop(BuildContext context, WidgetRef ref, List<MissionStop> existing) async {
    final title = TextEditingController();
    final lat = TextEditingController();
    final lng = TextEditingController();
    final radius = TextEditingController(text: '150');
    var requiresQr = true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Add stop'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: lat,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration:
                        const InputDecoration(labelText: 'Latitude', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: lng,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration:
                        const InputDecoration(labelText: 'Longitude', border: OutlineInputBorder()),
                  ),
                ),
              ]),
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
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    if (saved != true || title.text.trim().isEmpty) return;
    final nextSequence =
        existing.isEmpty ? 1 : existing.map((s) => s.sequence).reduce((a, b) => a > b ? a : b) + 1;
    await ref.read(missionRepositoryProvider).createStop({
      'mission_id': mission.id,
      'sequence': nextSequence,
      'title': title.text.trim(),
      'latitude': double.tryParse(lat.text.trim()) ?? 0,
      'longitude': double.tryParse(lng.text.trim()) ?? 0,
      'arrival_radius_meters': double.tryParse(radius.text.trim()) ?? 150,
      'requires_qr': requiresQr,
    });
    ref.read(missionsRefreshProvider.notifier).bump();
  }
}
