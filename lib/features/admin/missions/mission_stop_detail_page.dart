import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_stop.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_travel_story.dart';
import 'package:explorer_os_mobile/features/missions/models/old_world.dart';

/// Admin -> one stop's content: arrival narration, travel/approach stories
/// (ADD TRAVEL STORY / ADD APPROACH STORY / ADD ARRIVAL STORY), the QR
/// portal (ASSIGN QR — shown as an actual scannable image), the Old World
/// (CREATE OLD WORLD / ADD CLUE, with images/narrator/characters), and
/// which stop comes next (ASSIGN NEXT STOP).
class MissionStopDetailPage extends ConsumerWidget {
  const MissionStopDetailPage({super.key, required this.mission, required this.stop});
  final Mission mission;
  final MissionStop stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(travelStoriesForStopProvider(stop.id));
    final allStopsAsync = ref.watch(missionStopsProvider(mission.id));
    final oldWorldAsync =
        stop.oldWorldId == null ? null : ref.watch(oldWorldByIdProvider(stop.oldWorldId!));

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
              onPressed: () => _addOrEditStory(context, ref),
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
                    for (final s in stories) _storyRow(context, ref, s),
                  ]),
          ),
          const SizedBox(height: 16),
          AdminSectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('QR Portal & Old World', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (stop.qrPortalId == null || stop.oldWorldId == null)
                FilledButton(
                  onPressed: () => _createQrAndOldWorld(context, ref),
                  child: const Text('Create QR Portal + Old World'),
                )
              else ...[
                _QrCodeDisplay(portalId: stop.qrPortalId!),
                const SizedBox(height: 16),
                if (oldWorldAsync != null)
                  oldWorldAsync.when(
                    loading: () => const CircularProgressIndicator(),
                    error: (e, _) => Text('$e'),
                    data: (world) => world == null
                        ? const Text('Old World content not found.')
                        : _OldWorldSummary(
                            world: world,
                            onEdit: () => showOldWorldEditorDialog(context, ref, world: world),
                          ),
                  ),
              ],
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

  Widget _storyRow(BuildContext context, WidgetRef ref, MissionTravelStory s) => AdminSectionCard(
        child: ListTile(
          leading: StatusBadge(
            s.isApproach ? BadgeStatus.review : BadgeStatus.published,
            label: s.isApproach ? 'Approach' : 'Travel',
          ),
          title: Text(s.text, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('At ${(s.triggerDistanceMeters / 1609.344).toStringAsFixed(2)} mi'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _addOrEditStory(context, ref, story: s),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await ref.read(missionRepositoryProvider).deleteTravelStory(s.id);
                ref.read(missionsRefreshProvider.notifier).bump();
              },
            ),
          ]),
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

  Future<void> _addOrEditStory(BuildContext context, WidgetRef ref, {MissionTravelStory? story}) async {
    final text = TextEditingController(text: story?.text ?? '');
    final distanceMiles = TextEditingController(
        text: story == null ? '' : (story.triggerDistanceMeters / 1609.344).toStringAsFixed(2));
    final speakerName = TextEditingController(text: story?.speakerName ?? '');
    final revealsFactKeys = TextEditingController(text: story?.revealsFactKeys.join(', ') ?? '');
    var triggerType = story?.triggerType ?? 'travel';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(story == null ? 'Add travel/approach story' : 'Edit story'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
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
                    controller: speakerName,
                    decoration: const InputDecoration(
                        labelText: 'Speaker (optional, e.g. "Thomas")',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                  controller: text,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Narration text', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: revealsFactKeys,
                  decoration: const InputDecoration(
                      labelText: 'Reveals fact keys (comma-separated, optional)',
                      helperText: 'The player may not know why yet — a later puzzle can ask about it.',
                      border: OutlineInputBorder()),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(story == null ? 'Add' : 'Save')),
          ],
        ),
      ),
    );

    if (saved != true || text.text.trim().isEmpty) return;
    final miles = double.tryParse(distanceMiles.text.trim()) ?? 1;
    final repo = ref.read(missionRepositoryProvider);
    final row = {
      'trigger_type': triggerType,
      'trigger_distance_meters': miles * 1609.344,
      'text': text.text.trim(),
      'speaker_name': speakerName.text.trim().isEmpty ? null : speakerName.text.trim(),
      'reveals_fact_keys': revealsFactKeys.text
          .split(',')
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList(),
    };
    if (story == null) {
      await repo.createTravelStory({...row, 'mission_id': mission.id, 'stop_id': stop.id});
    } else {
      await repo.updateTravelStory(story.id, row);
    }
    ref.read(missionsRefreshProvider.notifier).bump();
  }

  Future<void> _createQrAndOldWorld(BuildContext context, WidgetRef ref) async {
    final code = TextEditingController(text: 'MCA-${stop.id.substring(0, 8).toUpperCase()}');
    final title = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create QR Portal + Old World'),
        content: SizedBox(
          width: 380,
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
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Create')),
        ],
      ),
    );

    if (saved != true || title.text.trim().isEmpty) return;
    final repo = ref.read(missionRepositoryProvider);
    final oldWorldId = await repo.createOldWorld({
      'title': title.text.trim(),
      'is_fictional': true,
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

/// Renders the QR portal's actual scannable code — closing the gap flagged
/// after Phase 6 ("no printable QR image generated yet"). Pure client-side
/// rendering (`qr_flutter`, no native dependency), from the exact [code]
/// string `QrScanScreen`/`onQrScanned` already expect to read back.
class _QrCodeDisplay extends ConsumerWidget {
  const _QrCodeDisplay({required this.portalId});
  final String portalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Portals aren't independently cached — reused inline via a one-off
    // fetch through the repository rather than adding a new provider for a
    // single admin-only display, since nothing else in the app needs to
    // watch an individual portal by id.
    return FutureBuilder(
      future: ref.read(missionRepositoryProvider).portalById(portalId),
      builder: (context, snapshot) {
        final portal = snapshot.data;
        if (portal == null) return const SizedBox.shrink();
        return Row(children: [
          QrImageView(data: portal.code, size: 96, backgroundColor: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('QR code', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              SelectableText(portal.code),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: portal.code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Code copied.')));
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy code'),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}

class _OldWorldSummary extends StatelessWidget {
  const _OldWorldSummary({required this.world, required this.onEdit});
  final OldWorld world;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(world.title, style: const TextStyle(fontWeight: FontWeight.w700))),
        StatusBadge(
          world.isFictional ? BadgeStatus.draft : BadgeStatus.published,
          label: world.isFictional ? 'Fictional' : 'Verified history',
        ),
      ]),
      if ((world.narrationText ?? '').isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(world.narrationText!, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
      const SizedBox(height: 8),
      OutlinedButton(onPressed: onEdit, child: const Text('Edit Old World')),
    ]);
  }
}

/// The full Old World editor — historical period, images, narrator,
/// characters (add/remove), narration, clue, and the fictional/verified
/// designation. Reused for both the initial (minimal) row created alongside
/// a QR portal and later enrichment.
Future<void> showOldWorldEditorDialog(
  BuildContext context,
  WidgetRef ref, {
  required OldWorld world,
}) async {
  final title = TextEditingController(text: world.title);
  final period = TextEditingController(text: world.historicalPeriod ?? '');
  final narration = TextEditingController(text: world.narrationText ?? '');
  final heroImage = TextEditingController(text: world.heroImageUrl ?? '');
  final mapImage = TextEditingController(text: world.historicalMapImageUrl ?? '');
  final narrator = TextEditingController(text: world.narratorName ?? '');
  final clue = TextEditingController(text: world.clueText ?? '');
  final revealsFactKeys = TextEditingController(text: world.revealsFactKeys.join(', '));
  var isFictional = world.isFictional;
  final characters = [...world.characters];

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Edit Old World'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: title,
                  decoration:
                      const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: period,
                  decoration: const InputDecoration(
                      labelText: 'Historical period (e.g. "1880s")',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                controller: narration,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Narration', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: heroImage,
                  decoration: const InputDecoration(
                      labelText: 'Hero image URL', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: mapImage,
                  decoration: const InputDecoration(
                      labelText: 'Historical map image URL (optional)',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: narrator,
                  decoration: const InputDecoration(
                      labelText: 'Narrator name (optional)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: clue,
                  decoration: const InputDecoration(
                      labelText: 'Clue (optional)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: revealsFactKeys,
                  decoration: const InputDecoration(
                      labelText: 'Reveals fact keys (comma-separated, optional)',
                      border: OutlineInputBorder())),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fictional story'),
                subtitle: const Text('Off = verified history — only turn off with a real source.'),
                value: isFictional,
                onChanged: (v) => setState(() => isFictional = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Characters', style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(
                      () => characters.add(const OldWorldCharacter(name: 'New character'))),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add'),
                ),
              ]),
              for (var i = 0; i < characters.length; i++)
                _CharacterEditorRow(
                  character: characters[i],
                  onChanged: (c) => setState(() => characters[i] = c),
                  onRemove: () => setState(() => characters.removeAt(i)),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await ref.read(missionRepositoryProvider).updateOldWorld(world.id, {
                'title': title.text.trim(),
                'historical_period': period.text.trim().isEmpty ? null : period.text.trim(),
                'narration_text': narration.text.trim().isEmpty ? null : narration.text.trim(),
                'hero_image_url': heroImage.text.trim().isEmpty ? null : heroImage.text.trim(),
                'historical_map_image_url':
                    mapImage.text.trim().isEmpty ? null : mapImage.text.trim(),
                'narrator_name': narrator.text.trim().isEmpty ? null : narrator.text.trim(),
                'clue_text': clue.text.trim().isEmpty ? null : clue.text.trim(),
                'reveals_fact_keys': revealsFactKeys.text
                    .split(',')
                    .map((k) => k.trim())
                    .where((k) => k.isNotEmpty)
                    .toList(),
                'is_fictional': isFictional,
                'characters': characters.map((c) => c.toJson()).toList(),
              });
              ref.read(missionsRefreshProvider.notifier).bump();
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

class _CharacterEditorRow extends StatefulWidget {
  const _CharacterEditorRow({required this.character, required this.onChanged, required this.onRemove});
  final OldWorldCharacter character;
  final ValueChanged<OldWorldCharacter> onChanged;
  final VoidCallback onRemove;

  @override
  State<_CharacterEditorRow> createState() => _CharacterEditorRowState();
}

class _CharacterEditorRowState extends State<_CharacterEditorRow> {
  late final _name = TextEditingController(text: widget.character.name);
  late final _description = TextEditingController(text: widget.character.description ?? '');
  late final _imageUrl = TextEditingController(text: widget.character.imageUrl ?? '');

  void _emit() => widget.onChanged(OldWorldCharacter(
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        imageUrl: _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
      ));

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _name,
                onChanged: (_) => _emit(),
                decoration: const InputDecoration(labelText: 'Name', isDense: true),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: widget.onRemove,
            ),
          ]),
          TextField(
            controller: _description,
            onChanged: (_) => _emit(),
            decoration: const InputDecoration(labelText: 'Description', isDense: true),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _imageUrl,
            onChanged: (_) => _emit(),
            decoration: const InputDecoration(labelText: 'Image URL (optional)', isDense: true),
          ),
        ]),
      ),
    );
  }
}
