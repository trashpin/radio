import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/guide_step.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_map_piece.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_puzzle.dart';
import 'package:explorer_os_mobile/features/missions/services/heygen_avatar_service.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';

const _kGuideStepsTable = 'guide_steps';

/// Admin -> Guide Steps: an adventure's own Guide sequence — always
/// delivered by THE GUIDE, distinct from Story Builder's
/// `mission_story_steps` (the adventure CHARACTERS' own story). Reuses
/// `mission_puzzles` for RIDDLE/QUESTION answer-checking + hints and
/// `mission_map_pieces` for CLUE/MAP/DISCOVERY unlocks rather than
/// duplicating either.
class GuideStepBuilderPage extends ConsumerWidget {
  const GuideStepBuilderPage({super.key, required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stepsAsync = ref.watch(allGuideStepsForMissionProvider(mission.id));
    final charactersAsync = ref.watch(missionCharactersProvider);
    final puzzlesAsync = ref.watch(puzzlesForMissionProvider(mission.id));
    final mapPiecesAsync = ref.watch(mapPiecesForMissionProvider(mission.id));

    return Scaffold(
      appBar: AppBar(title: Text('Guide Steps — ${mission.title}')),
      body: stepsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmptyState(message: 'Could not load Guide Steps: $e'),
        data: (steps) {
          final characters = charactersAsync.value ?? const [];
          final puzzles = puzzlesAsync.value ?? const [];
          final mapPieces = mapPiecesAsync.value ?? const [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdminPageHeader(
                title: mission.title,
                subtitle: '${steps.length} Guide step${steps.length == 1 ? '' : 's'} — always '
                    'delivered by THE GUIDE, shown when their trigger is satisfied.',
                actions: [
                  FilledButton.icon(
                    onPressed: () => _showStepEditorDialog(
                      context,
                      ref,
                      mission: mission,
                      characters: characters,
                      puzzles: puzzles,
                      mapPieces: mapPieces,
                      nextOrder: steps.isEmpty ? 1 : steps.last.stepOrder + 1,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Guide Step'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (steps.isEmpty)
                const AdminEmptyState(
                  message: 'No Guide Steps yet. Add one to start the Guide sequence.',
                  icon: Icons.person_search_outlined,
                )
              else
                for (var i = 0; i < steps.length; i++)
                  _StepRow(
                    step: steps[i],
                    index: i,
                    total: steps.length,
                    mission: mission,
                    characters: characters,
                    puzzles: puzzles,
                    mapPieces: mapPieces,
                    character: characters.where((c) => c.id == steps[i].characterId).firstOrNull,
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _StepRow extends ConsumerStatefulWidget {
  const _StepRow({
    required this.step,
    required this.index,
    required this.total,
    required this.mission,
    required this.characters,
    required this.puzzles,
    required this.mapPieces,
    required this.character,
  });
  final GuideStep step;
  final int index;
  final int total;
  final Mission mission;
  final List<MissionCharacter> characters;
  final List<MissionPuzzle> puzzles;
  final List<MissionMapPiece> mapPieces;
  final MissionCharacter? character;

  @override
  ConsumerState<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends ConsumerState<_StepRow> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _busy = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _preview() async {
    final url = widget.step.audioUrl;
    if ((url ?? '').isEmpty) return;
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
      return;
    }
    try {
      setState(() => _playing = true);
      await _player.setUrl(url!);
      await _player.play();
      _player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed && mounted) {
          setState(() => _playing = false);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _generateVoice({bool force = false}) async {
    final step = widget.step;
    final script = (step.script ?? '').trim();
    if (script.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Write a script first.')));
      return;
    }
    setState(() => _busy = true);
    final result = await ref.read(missionNarrationServiceProvider).requestFor(
          subjectId: 'guide-step:${step.id}',
          kind: 'guide',
          subjectType: 'guide',
          text: script,
          voiceId: widget.character?.voiceId,
          force: force,
        );
    if (result?.audioUrl != null) {
      await ref.read(missionRepositoryProvider).updateGuideStep(step.id, {
        'audio_url': result!.audioUrl,
        'production_status': kGuideStepStatusReady,
      });
      ref.read(missionsRefreshProvider.notifier).bump();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Voice generation failed.')));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _generateAvatar() async {
    final step = widget.step;
    final character = widget.character;
    if (!step.hasAudio) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Generate this step\'s voice first — the avatar lip-syncs to that audio.')));
      return;
    }
    if ((character?.heygenAvatarId ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(character == null
              ? 'Select a character with a HeyGen Avatar ID first.'
              : '${character.name} has no HeyGen Avatar ID assigned.')));
      return;
    }
    setState(() => _busy = true);
    String? failure;
    final started = await ref.read(heyGenAvatarServiceProvider).generate(
          stepId: step.id,
          table: _kGuideStepsTable,
          avatarId: character!.heygenAvatarId!,
          avatarType: character.heygenAvatarType,
          audioUrl: step.audioUrl!,
          onError: (m) => failure = m,
        );
    if (!started) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Avatar generation failed: ${failure ?? 'unknown error'}')));
      }
      return;
    }
    ref.read(missionsRefreshProvider.notifier).bump();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Avatar video is rendering — use "Check Avatar Status" shortly.')));
      setState(() => _busy = false);
    }
  }

  Future<void> _checkAvatarStatus() async {
    setState(() => _busy = true);
    final result = await ref
        .read(heyGenAvatarServiceProvider)
        .checkStatus(widget.step.id, table: _kGuideStepsTable);
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (result.isCompleted) {
      ref.read(missionsRefreshProvider.notifier).bump();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Avatar video is ready.')));
    } else if (result.isFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Avatar render failed: ${result.error ?? 'unknown error'}')));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Still rendering — check again shortly.')));
    }
  }

  Future<void> _move(int delta) async {
    final steps =
        await ref.read(missionRepositoryProvider).allGuideStepsForMission(widget.mission.id);
    final i = steps.indexWhere((s) => s.id == widget.step.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= steps.length) return;
    final a = steps[i], b = steps[j];
    final repo = ref.read(missionRepositoryProvider);
    await repo.updateGuideStep(a.id, {'step_order': b.stepOrder});
    await repo.updateGuideStep(b.id, {'step_order': a.stepOrder});
    ref.read(missionsRefreshProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    return AdminSectionCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(children: [
              Text('${widget.index + 1}'.padLeft(2, '0'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                onPressed: widget.index == 0 ? null : () => _move(-1),
                tooltip: 'Move earlier',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                onPressed: widget.index == widget.total - 1 ? null : () => _move(1),
                tooltip: 'Move later',
              ),
            ]),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child:
                            Text(step.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (!step.active) _tag('inactive'),
                  ]),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _tag(step.contentType, icon: Icons.category_outlined),
                    if (widget.character != null) _tag(widget.character!.name, icon: Icons.person),
                    _tag(step.triggerType.replaceAll('_', ' '), icon: Icons.gps_fixed_rounded),
                    if (step.evidenceType != null)
                      _tag(evidenceTypeLabel(step.evidenceType!), icon: Icons.movie_filter_outlined),
                  ]),
                  if ((step.script ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(step.script!, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    OutlinedButton.icon(
                      onPressed: () => _showStepEditorDialog(
                        context,
                        ref,
                        mission: widget.mission,
                        characters: widget.characters,
                        puzzles: widget.puzzles,
                        mapPieces: widget.mapPieces,
                        step: step,
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _generateVoice(force: step.hasAudio),
                      icon: const Icon(Icons.record_voice_over_rounded, size: 16),
                      label: Text(step.hasAudio ? 'Regenerate Voice' : 'Generate Voice'),
                    ),
                    if (step.hasAudio)
                      OutlinedButton.icon(
                        onPressed: _preview,
                        icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 16),
                        label: Text(_playing ? 'Stop' : 'Preview'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _generateAvatar,
                      icon: const Icon(Icons.videocam_outlined, size: 16),
                      label: Text(step.heygenVideoId == null ? 'Generate Avatar' : 'Regenerate Avatar'),
                    ),
                    if (step.heygenVideoId != null && !step.hasAvatarVideo)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _checkAvatarStatus,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Check Avatar Status'),
                      ),
                    if (step.hasAvatarVideo)
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri.parse(step.avatarVideoUrl!),
                            mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
                        label: const Text('View Avatar Video'),
                      ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () async {
                        await ref.read(missionRepositoryProvider).deleteGuideStep(step.id);
                        ref.read(missionsRefreshProvider.notifier).bump();
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12), const SizedBox(width: 3)],
          Text(label, style: const TextStyle(fontSize: 11)),
        ]),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

Future<void> _showStepEditorDialog(
  BuildContext context,
  WidgetRef ref, {
  required Mission mission,
  required List<MissionCharacter> characters,
  required List<MissionPuzzle> puzzles,
  required List<MissionMapPiece> mapPieces,
  GuideStep? step,
  int nextOrder = 1,
}) async {
  final title = TextEditingController(text: step?.title ?? '');
  final script = TextEditingController(text: step?.script ?? '');
  final imageUrl = TextEditingController(text: step?.imageUrl ?? '');
  final triggerDistanceMiles = TextEditingController(
      text: step?.triggerDistanceMeters == null
          ? ''
          : (step!.triggerDistanceMeters! / 1609.344).toStringAsFixed(2));
  final choices = [...step?.choiceOptions ?? const []];
  var contentType = step?.contentType ?? kGuideContentTalk;
  var characterId = step?.characterId;
  var puzzleId = step?.puzzleId;
  var unlocksMapPieceId = step?.unlocksMapPieceId;
  var evidenceType = step?.evidenceType;
  var triggerType = step?.triggerType ?? kGuideTriggerManualDiscovery;
  var active = step?.active ?? true;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(step == null ? 'Add Guide Step' : 'Edit Guide Step'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: title,
                  decoration: const InputDecoration(
                      labelText: 'Step title (admin-only)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: contentType,
                decoration:
                    const InputDecoration(labelText: 'Content type', border: OutlineInputBorder()),
                items: [
                  for (final t in kGuideContentTypes)
                    DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' '))),
                ],
                onChanged: (v) => setState(() => contentType = v ?? contentType),
              ),
              if (contentType == kGuideContentVideo ||
                  contentType == kGuideContentAudio ||
                  contentType == kGuideContentImage ||
                  contentType == kGuideContentInspect ||
                  contentType == kGuideContentClue) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: evidenceType,
                  decoration: const InputDecoration(
                      labelText: 'Evidence type (optional — marks this HISTORICAL EVIDENCE)',
                      border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— not evidence, this is the Guide —')),
                    for (final t in kEvidenceTypes)
                      DropdownMenuItem(value: t, child: Text(evidenceTypeLabel(t))),
                  ],
                  onChanged: (v) => setState(() => evidenceType = v),
                ),
                if (evidenceType != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Shown with an archived, period visual treatment and voiced/appeared by the '
                      'character selected below — not the Guide.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: characters.any((c) => c.id == characterId) ? characterId : null,
                decoration: InputDecoration(
                    labelText: evidenceType != null
                        ? 'Historical character (their existing voice + HeyGen avatar)'
                        : 'Character override (optional — defaults to the active Guide)',
                    border: const OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— use the active Guide —')),
                  for (final c in characters) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => characterId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: triggerType,
                decoration:
                    const InputDecoration(labelText: 'Trigger', border: OutlineInputBorder()),
                items: [
                  for (final t in kGuideTriggerTypes)
                    DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' '))),
                ],
                onChanged: (v) => setState(() => triggerType = v ?? triggerType),
              ),
              if (triggerType == kGuideTriggerDistanceFromDestination) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: triggerDistanceMiles,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Trigger distance (miles)', border: OutlineInputBorder()),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: script,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'What the Guide says', border: OutlineInputBorder()),
              ),
              if (contentType == kGuideContentImage || contentType == kGuideContentInspect) ...[
                const SizedBox(height: 12),
                TextField(
                    controller: imageUrl,
                    decoration:
                        const InputDecoration(labelText: 'Image URL', border: OutlineInputBorder())),
              ],
              if (contentType == kGuideContentRiddle || contentType == kGuideContentQuestion) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: puzzles.any((p) => p.id == puzzleId) ? puzzleId : null,
                  decoration: const InputDecoration(
                      labelText: 'Puzzle (reuses its prompt, answers, and hints)',
                      border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— none —')),
                    for (final p in puzzles)
                      DropdownMenuItem(value: p.id, child: Text(p.prompt, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => puzzleId = v),
                ),
              ],
              if (triggerType == kGuideTriggerPuzzleSolved) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: puzzles.any((p) => p.id == puzzleId) ? puzzleId : null,
                  decoration: const InputDecoration(
                      labelText: 'Fires once THIS puzzle is solved', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— none —')),
                    for (final p in puzzles)
                      DropdownMenuItem(value: p.id, child: Text(p.prompt, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => puzzleId = v),
                ),
              ],
              if (contentType == kGuideContentClue ||
                  contentType == kGuideContentMap ||
                  contentType == kGuideContentDiscovery) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue:
                      mapPieces.any((p) => p.id == unlocksMapPieceId) ? unlocksMapPieceId : null,
                  decoration: const InputDecoration(
                      labelText: 'Unlocks map piece (optional)', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— none —')),
                    for (final p in mapPieces) DropdownMenuItem(value: p.id, child: Text(p.title)),
                  ],
                  onChanged: (v) => setState(() => unlocksMapPieceId = v),
                ),
              ],
              if (contentType == kGuideContentChoice) ...[
                const SizedBox(height: 20),
                Row(children: [
                  const Expanded(child: Text('Choice options', style: TextStyle(fontWeight: FontWeight.w700))),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => choices.add(const GuideChoiceOption(label: '', response: ''))),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add'),
                  ),
                ]),
                const Text(
                  'Does not branch the route or mission graph — each option is a label plus a '
                  'follow-up line only.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                for (var i = 0; i < choices.length; i++)
                  _ChoiceOptionEditorRow(
                    option: choices[i],
                    onChanged: (o) => setState(() => choices[i] = o),
                    onRemove: () => setState(() => choices.removeAt(i)),
                  ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged: (v) => setState(() => active = v),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(step == null ? 'Add' : 'Save')),
        ],
      ),
    ),
  );

  if (saved != true || title.text.trim().isEmpty) return;
  final miles = double.tryParse(triggerDistanceMiles.text.trim());
  final row = {
    'mission_id': mission.id,
    'title': title.text.trim(),
    'content_type': contentType,
    'character_id': characterId,
    'script': script.text.trim().isEmpty ? null : script.text.trim(),
    'image_url': imageUrl.text.trim().isEmpty ? null : imageUrl.text.trim(),
    'puzzle_id': puzzleId,
    'unlocks_map_piece_id': unlocksMapPieceId,
    'evidence_type': evidenceType,
    'choice_options': choices.where((c) => c.label.trim().isNotEmpty).map((c) => c.toJson()).toList(),
    'trigger_type': triggerType,
    'trigger_distance_meters': miles == null ? null : miles * 1609.344,
    'active': active,
  };
  final repo = ref.read(missionRepositoryProvider);
  if (step == null) {
    row['step_order'] = nextOrder;
    row['production_status'] = kGuideStepStatusDraft;
    await repo.createGuideStep(row);
  } else {
    await repo.updateGuideStep(step.id, row);
  }
  ref.read(missionsRefreshProvider.notifier).bump();
}

class _ChoiceOptionEditorRow extends StatefulWidget {
  const _ChoiceOptionEditorRow({required this.option, required this.onChanged, required this.onRemove});
  final GuideChoiceOption option;
  final ValueChanged<GuideChoiceOption> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ChoiceOptionEditorRow> createState() => _ChoiceOptionEditorRowState();
}

class _ChoiceOptionEditorRowState extends State<_ChoiceOptionEditorRow> {
  late final _label = TextEditingController(text: widget.option.label);
  late final _response = TextEditingController(text: widget.option.response);

  void _emit() => widget.onChanged(GuideChoiceOption(label: _label.text, response: _response.text));

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
                controller: _label,
                onChanged: (_) => _emit(),
                decoration: const InputDecoration(labelText: 'Option label', isDense: true),
              ),
            ),
            IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: widget.onRemove),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: _response,
            onChanged: (_) => _emit(),
            decoration: const InputDecoration(labelText: 'Follow-up response', isDense: true),
          ),
        ]),
      ),
    );
  }
}
