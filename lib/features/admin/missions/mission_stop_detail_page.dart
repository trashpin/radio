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
import 'package:explorer_os_mobile/features/missions/models/treasure_discovery.dart';

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
    final treasureAsync = stop.treasureDiscoveryId == null
        ? null
        : ref.watch(treasureDiscoveryByIdProvider(stop.treasureDiscoveryId!));

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
              Row(children: [
                Expanded(
                    child: Text('Treasure Discovery', style: Theme.of(context).textTheme.titleMedium)),
                if (stop.qrPortalId == null)
                  const Text('Needs a QR Portal first', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
              const Text(
                'Stage 2 after GPS arrival: a stylized map + clue that makes the player explore '
                'before reaching the QR marker. GPS still gets them to this stop\'s arrival radius; '
                'this never reveals the exact QR spot. Uses this stop\'s existing QR Portal above — '
                'no second QR system.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              if (stop.treasureDiscoveryId == null)
                FilledButton(
                  onPressed: stop.qrPortalId == null
                      ? null
                      : () => _createTreasureDiscovery(context, ref),
                  child: const Text('Create Treasure Discovery'),
                )
              else if (treasureAsync != null)
                treasureAsync.when(
                  loading: () => const CircularProgressIndicator(),
                  error: (e, _) => Text('$e'),
                  data: (discovery) => discovery == null
                      ? const Text('Treasure discovery not found.')
                      : _TreasureDiscoverySummary(
                          discovery: discovery,
                          onEdit: () =>
                              showTreasureDiscoveryEditorDialog(context, ref, discovery: discovery),
                        ),
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
    final characters = await ref.read(missionRepositoryProvider).allCharacters();
    var arrivalCharacterId = stop.arrivalCharacterId;
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Arrival narration'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (characters.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue:
                      characters.any((c) => c.id == arrivalCharacterId) ? arrivalCharacterId : null,
                  decoration: const InputDecoration(
                      labelText: 'Character speaking on arrival', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— narrator / global default —')),
                    for (final c in characters) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => arrivalCharacterId = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await ref.read(missionRepositoryProvider).updateStop(stop.id, {
      'arrival_narration_text': controller.text.trim(),
      'arrival_character_id': arrivalCharacterId,
    });
    ref.read(missionsRefreshProvider.notifier).bump();
  }

  Future<void> _addOrEditStory(BuildContext context, WidgetRef ref, {MissionTravelStory? story}) async {
    final text = TextEditingController(text: story?.text ?? '');
    final distanceMiles = TextEditingController(
        text: story == null ? '' : (story.triggerDistanceMeters / 1609.344).toStringAsFixed(2));
    final speakerName = TextEditingController(text: story?.speakerName ?? '');
    final revealsFactKeys = TextEditingController(text: story?.revealsFactKeys.join(', ') ?? '');
    var triggerType = story?.triggerType ?? 'travel';
    var characterId = story?.characterId;
    final characters = await ref.read(missionRepositoryProvider).allCharacters();

    if (!context.mounted) return;
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
                if (characters.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    initialValue: characters.any((c) => c.id == characterId) ? characterId : null,
                    decoration: const InputDecoration(
                        labelText: 'Character', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— none / use free text below —')),
                      for (final c in characters) DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => characterId = v),
                  ),
                const SizedBox(height: 12),
                TextField(
                    controller: speakerName,
                    decoration: const InputDecoration(
                        labelText: 'Or: speaker name as free text (no character record)',
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
      'character_id': characterId,
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

  Future<void> _createTreasureDiscovery(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(missionRepositoryProvider);
    final id = await repo.createTreasureDiscovery({'mission_id': mission.id, 'stop_id': stop.id});
    await repo.updateStop(stop.id, {'treasure_discovery_id': id});
    ref.read(missionsRefreshProvider.notifier).bump();
    if (context.mounted) {
      final discovery = await repo.treasureDiscoveryById(id);
      if (discovery != null && context.mounted) {
        await showTreasureDiscoveryEditorDialog(context, ref, discovery: discovery);
      }
    }
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
  final castCharacters = [...world.characters];
  var narratingCharacterId = world.characterId;
  final missionCharacters = await ref.read(missionRepositoryProvider).allCharacters();

  if (!context.mounted) return;
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
              if (missionCharacters.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: missionCharacters.any((c) => c.id == narratingCharacterId)
                      ? narratingCharacterId
                      : null,
                  decoration: const InputDecoration(
                      labelText: 'Character narrating this reveal',
                      helperText: 'Their assigned voice is reused — same voice as their other scenes.',
                      border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— none / use free text below —')),
                    for (final c in missionCharacters) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => narratingCharacterId = v),
                ),
              const SizedBox(height: 12),
              TextField(
                  controller: narrator,
                  decoration: const InputDecoration(
                      labelText: 'Or: narrator name as free text (no character record)',
                      border: OutlineInputBorder())),
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
                const Text('Cast (descriptive only, no voice)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(
                      () => castCharacters.add(const OldWorldCharacter(name: 'New character'))),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add'),
                ),
              ]),
              for (var i = 0; i < castCharacters.length; i++)
                _CharacterEditorRow(
                  character: castCharacters[i],
                  onChanged: (c) => setState(() => castCharacters[i] = c),
                  onRemove: () => setState(() => castCharacters.removeAt(i)),
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
                'character_id': narratingCharacterId,
                'clue_text': clue.text.trim().isEmpty ? null : clue.text.trim(),
                'reveals_fact_keys': revealsFactKeys.text
                    .split(',')
                    .map((k) => k.trim())
                    .where((k) => k.isNotEmpty)
                    .toList(),
                'is_fictional': isFictional,
                'characters': castCharacters.map((c) => c.toJson()).toList(),
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

class _TreasureDiscoverySummary extends StatelessWidget {
  const _TreasureDiscoverySummary({required this.discovery, required this.onEdit});
  final TreasureDiscovery discovery;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(discovery.discoveryTitle ?? 'Treasure Discovery',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        if ((discovery.difficulty ?? '').isNotEmpty) StatusBadge(BadgeStatus.review, label: discovery.difficulty!),
      ]),
      if ((discovery.clueText ?? '').isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(discovery.clueText!, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
      const SizedBox(height: 4),
      Text(
        [
          if (discovery.hasMapImage) 'map set' else 'no map yet (placeholder shown)',
          if (discovery.hasHint1 || discovery.hasHint2 || discovery.hasFinalHint)
            '${[discovery.hasHint1, discovery.hasHint2, discovery.hasFinalHint].where((b) => b).length} hint(s)'
          else
            'no hints',
        ].join(' · '),
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: onEdit, child: const Text('Edit Treasure Discovery')),
    ]);
  }
}

/// The Treasure Discovery editor — map image URL, clue, progressive hint
/// ladder, discovery title/difficulty, and optional search-area guidance.
/// Deliberately has no QR-picker field of its own: this stage always
/// resolves through the stop's OWN existing `qr_portal_id`, so there is
/// nothing to duplicate here (spec: "The QR itself should not be
/// duplicated"). Reused for both the initial (minimal) row created
/// alongside the stop and later enrichment, exactly like
/// [showOldWorldEditorDialog].
Future<void> showTreasureDiscoveryEditorDialog(
  BuildContext context,
  WidgetRef ref, {
  required TreasureDiscovery discovery,
}) async {
  final mapImageUrl = TextEditingController(text: discovery.treasureMapImageUrl ?? '');
  final clueText = TextEditingController(text: discovery.clueText ?? '');
  final hint1 = TextEditingController(text: discovery.hint1Text ?? '');
  final hint2 = TextEditingController(text: discovery.hint2Text ?? '');
  final finalHint = TextEditingController(text: discovery.finalHintText ?? '');
  final discoveryTitle = TextEditingController(text: discovery.discoveryTitle ?? '');
  final landmarksText = TextEditingController(text: discovery.landmarksText ?? '');
  final searchAreaFeet = TextEditingController(
      text: discovery.searchAreaMeters == null
          ? ''
          : (discovery.searchAreaMeters! * 3.28084).round().toString());
  var difficulty = discovery.difficulty;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Edit Treasure Discovery'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: mapImageUrl,
                  decoration: const InputDecoration(
                      labelText: 'Treasure map image URL (optional — placeholder shown if empty)',
                      helperText: 'Mystery/adventure artwork of the real area — never a GPS map, '
                          'never a pin on the exact QR spot.',
                      border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                controller: clueText,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Clue',
                    helperText: 'Short, solvable, connected to the real location — e.g. "Follow '
                        'the trail toward the old trees. When the path bends, look for something '
                        'that has stood here longer than the trail itself."',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: hint1,
                  decoration: const InputDecoration(
                      labelText: 'Hint 1 (subtle, optional)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: hint2,
                  decoration: const InputDecoration(
                      labelText: 'Hint 2 — stronger (optional)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: finalHint,
                  decoration: const InputDecoration(
                      labelText: 'Final hint — makes it easy (optional)',
                      border: OutlineInputBorder())),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: discoveryTitle,
                    decoration: const InputDecoration(
                        labelText: 'Discovery title (optional, e.g. "YOU FOUND THE FIRST PIECE")',
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: difficulty,
                    decoration:
                        const InputDecoration(labelText: 'Difficulty', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final d in kTreasureDiscoveryDifficulties)
                        DropdownMenuItem(value: d, child: Text(d)),
                    ],
                    onChanged: (v) => setState(() => difficulty = v),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: searchAreaFeet,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Search area radius in feet (optional)',
                    helperText: 'Shown to the player as a soft bound, e.g. "somewhere within '
                        'about 300 feet of here" — never the exact QR distance.',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: landmarksText,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Landmarks (admin notes, optional)',
                      helperText: 'Production reference only — not shown to the player as-is.',
                      border: OutlineInputBorder())),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final feet = double.tryParse(searchAreaFeet.text.trim());
              await ref.read(missionRepositoryProvider).updateTreasureDiscovery(discovery.id, {
                'treasure_map_image_url':
                    mapImageUrl.text.trim().isEmpty ? null : mapImageUrl.text.trim(),
                'clue_text': clueText.text.trim().isEmpty ? null : clueText.text.trim(),
                'hint_1_text': hint1.text.trim().isEmpty ? null : hint1.text.trim(),
                'hint_2_text': hint2.text.trim().isEmpty ? null : hint2.text.trim(),
                'final_hint_text': finalHint.text.trim().isEmpty ? null : finalHint.text.trim(),
                'discovery_title':
                    discoveryTitle.text.trim().isEmpty ? null : discoveryTitle.text.trim(),
                'landmarks_text':
                    landmarksText.text.trim().isEmpty ? null : landmarksText.text.trim(),
                'difficulty': difficulty,
                'search_area_meters': feet == null ? null : feet / 3.28084,
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
