import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_stop.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_travel_story.dart';

/// Admin -> one stop's content: arrival narration, travel/approach stories
/// (ADD TRAVEL STORY / ADD APPROACH STORY / ADD ARRIVAL STORY), the QR
/// portal (ASSIGN QR), the Old World (CREATE OLD WORLD / ADD CLUE), and
/// which stop comes next (ASSIGN NEXT STOP).
class MissionStopDetailPage extends ConsumerWidget {
  const MissionStopDetailPage({super.key, required this.mission, required this.stop});
  final Mission mission;
  final MissionStop stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(travelStoriesForStopProvider(stop.id));
    final allStopsAsync = ref.watch(missionStopsProvider(mission.id));

    return Scaffold(
      appBar: AppBar(title: Text(stop.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AdminSectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Arrival', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(stop.arrivalNarrationText ?? '(no arrival narration set)'),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _editArrivalText(context, ref),
                child: const Text('Edit arrival narration'),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Text('Travel & Approach Stories', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _addStory(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ]),
          storiesAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => AdminEmptyState(message: 'Could not load stories: $e'),
            data: (stories) => stories.isEmpty
                ? const AdminEmptyState(message: 'No travel stories yet.')
                : Column(children: [
                    for (final s in stories) _storyRow(s),
                  ]),
          ),
          const SizedBox(height: 16),
          AdminSectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('QR Portal & Old World', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(stop.qrPortalId == null
                  ? 'No QR portal assigned yet.'
                  : 'QR portal assigned.'),
              Text(stop.oldWorldId == null
                  ? 'No Old World content yet.'
                  : 'Old World content assigned.'),
              const SizedBox(height: 8),
              if (stop.qrPortalId == null || stop.oldWorldId == null)
                FilledButton(
                  onPressed: () => _createQrAndOldWorld(context, ref),
                  child: const Text('Create QR Portal + Old World'),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          AdminSectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Next Stop', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              allStopsAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (allStops) {
                  final others = allStops.where((s) => s.id != stop.id).toList();
                  return DropdownButton<String?>(
                    value: stop.nextStopId,
                    hint: const Text('None (last stop)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None (last stop)')),
                      for (final s in others)
                        DropdownMenuItem(value: s.id, child: Text('${s.sequence}. ${s.title}')),
                    ],
                    onChanged: (v) async {
                      await ref
                          .read(missionRepositoryProvider)
                          .updateStop(stop.id, {'next_stop_id': v});
                      ref.read(missionsRefreshProvider.notifier).bump();
                    },
                  );
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _storyRow(MissionTravelStory s) => AdminSectionCard(
        child: ListTile(
          leading: StatusBadge(
            s.isApproach ? BadgeStatus.review : BadgeStatus.published,
            label: s.isApproach ? 'Approach' : 'Travel',
          ),
          title: Text(s.text, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('At ${(s.triggerDistanceMeters / 1609.344).toStringAsFixed(2)} mi'),
        ),
      );

  Future<void> _editArrivalText(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: stop.arrivalNarrationText ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Arrival narration'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (text == null) return;
    await ref.read(missionRepositoryProvider).updateStop(stop.id, {'arrival_narration_text': text});
    ref.read(missionsRefreshProvider.notifier).bump();
  }

  Future<void> _addStory(BuildContext context, WidgetRef ref) async {
    final text = TextEditingController();
    final distanceMiles = TextEditingController();
    var triggerType = 'travel';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Add travel/approach story'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'travel', label: Text('Travel')),
                  ButtonSegment(value: 'approach', label: Text('Approach')),
                ],
                selected: {triggerType},
                onSelectionChanged: (s) => setState(() => triggerType = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: distanceMiles,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Trigger distance (miles from this stop)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Narration text', border: OutlineInputBorder()),
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

    if (saved != true || text.text.trim().isEmpty) return;
    final miles = double.tryParse(distanceMiles.text.trim()) ?? 1;
    await ref.read(missionRepositoryProvider).createTravelStory({
      'mission_id': mission.id,
      'stop_id': stop.id,
      'trigger_type': triggerType,
      'trigger_distance_meters': miles * 1609.344,
      'text': text.text.trim(),
    });
    ref.read(missionsRefreshProvider.notifier).bump();
  }

  Future<void> _createQrAndOldWorld(BuildContext context, WidgetRef ref) async {
    final code = TextEditingController(text: 'MCA-${stop.id.substring(0, 8).toUpperCase()}');
    final title = TextEditingController();
    final narration = TextEditingController();
    final clue = TextEditingController();
    var isFictional = true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Create QR Portal + Old World'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: code,
                    decoration: const InputDecoration(
                        labelText: 'QR code (printed on the physical marker)',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: title,
                    decoration: const InputDecoration(
                        labelText: 'Old World title', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                  controller: narration,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: 'Historical/story narration', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: clue,
                    decoration: const InputDecoration(
                        labelText: 'Clue (optional)', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fictional story'),
                  subtitle: const Text('Off = verified history — only turn off with a real source.'),
                  value: isFictional,
                  onChanged: (v) => setState(() => isFictional = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Create')),
          ],
        ),
      ),
    );

    if (saved != true || title.text.trim().isEmpty) return;
    final repo = ref.read(missionRepositoryProvider);
    final oldWorldId = await repo.createOldWorld({
      'title': title.text.trim(),
      'is_fictional': isFictional,
      'narration_text': narration.text.trim().isEmpty ? null : narration.text.trim(),
      'clue_text': clue.text.trim().isEmpty ? null : clue.text.trim(),
    });
    final qrPortalId = await repo.createQrPortal({
      'code': code.text.trim(),
      'mission_stop_id': stop.id,
      'old_world_id': oldWorldId,
    });
    await repo.updateStop(stop.id, {'qr_portal_id': qrPortalId, 'old_world_id': oldWorldId});
    ref.read(missionsRefreshProvider.notifier).bump();
  }
}
