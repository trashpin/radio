import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/missions/data/game_guide_repository.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/game_guide_step.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';
import 'package:explorer_os_mobile/features/missions/services/heygen_avatar_service.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';

const _kGuideTable = 'game_guide_steps';

/// Admin -> Game Guide: the permanent character who introduces Marion
/// County Adventures itself — not any one adventure's story. The Guide's
/// IDENTITY (name/image/personality/ElevenLabs voice/HeyGen avatar) is
/// still edited in the existing Character Manager, as a
/// `character_type = 'local_guide'` row — this page only owns the Guide's
/// CONTENT (`game_guide_steps`): the introduction, tutorial beats, and the
/// observation moment, played in order by `GuideIntroScreen`.
class GameGuideManagerPage extends ConsumerWidget {
  const GameGuideManagerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stepsAsync = ref.watch(allGuideStepsProvider);
    final characterAsync = ref.watch(activeGuideCharacterProvider);
    final allCharactersAsync = ref.watch(missionCharactersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Game Guide')),
      body: stepsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmptyState(message: 'Could not load Guide content: $e'),
        data: (steps) {
          final character = characterAsync.value;
          final allCharacters = allCharactersAsync.value ?? const [];
          final guideCharacters =
              allCharacters.where((c) => c.characterType == 'local_guide').toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdminPageHeader(
                title: 'The Guide',
                subtitle: character == null
                    ? 'No active local_guide character found — create one in Character '
                        'Manager (character_type = local_guide) first.'
                    : '${character.name} — identity (image/voice/avatar/personality) is '
                        'edited in Character Manager. This page only edits what the Guide says.',
                actions: [
                  FilledButton.icon(
                    onPressed: () => _showStepEditorDialog(
                      context,
                      ref,
                      characters: guideCharacters,
                      nextOrder: steps.isEmpty ? 1 : steps.last.stepOrder + 1,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Step'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (steps.isEmpty)
                const AdminEmptyState(
                  message: 'No Guide content yet. Add an introduction, a few tutorial beats, '
                      'and one observation step.',
                  icon: Icons.auto_stories_outlined,
                )
              else
                for (var i = 0; i < steps.length; i++)
                  _StepRow(
                    step: steps[i],
                    index: i,
                    total: steps.length,
                    characters: guideCharacters,
                    character: (guideCharacters.where((c) => c.id == steps[i].characterId)
                            .firstOrNull) ??
                        character,
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
    required this.characters,
    required this.character,
  });
  final GameGuideStep step;
  final int index;
  final int total;
  final List<MissionCharacter> characters;
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
      await ref.read(gameGuideRepositoryProvider).updateStep(step.id, {
        'audio_url': result!.audioUrl,
        'production_status': kGuideStatusReady,
      });
      ref.read(gameGuideRefreshProvider.notifier).bump();
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
          content: Text('Generate this step\'s voice first — the avatar lip-syncs to that '
              'exact audio.')));
      return;
    }
    if ((character?.heygenAvatarId ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(character == null
              ? 'Select a Guide character with a HeyGen Avatar ID first.'
              : '${character.name} has no HeyGen Avatar ID assigned — add one in Character Manager.')));
      return;
    }

    setState(() => _busy = true);
    String? failure;
    final started = await ref.read(heyGenAvatarServiceProvider).generate(
          stepId: step.id,
          table: _kGuideTable,
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
    ref.read(gameGuideRefreshProvider.notifier).bump();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Avatar video is rendering — use "Check Avatar Status" shortly.')));
      setState(() => _busy = false);
    }
  }

  Future<void> _checkAvatarStatus() async {
    setState(() => _busy = true);
    final result =
        await ref.read(heyGenAvatarServiceProvider).checkStatus(widget.step.id, table: _kGuideTable);
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;
    if (result.isCompleted) {
      ref.read(gameGuideRefreshProvider.notifier).bump();
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
    final steps = await ref.read(gameGuideRepositoryProvider).allSteps();
    final i = steps.indexWhere((s) => s.id == widget.step.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= steps.length) return;
    final a = steps[i], b = steps[j];
    final repo = ref.read(gameGuideRepositoryProvider);
    await repo.updateStep(a.id, {'step_order': b.stepOrder});
    await repo.updateStep(b.id, {'step_order': a.stepOrder});
    ref.read(gameGuideRefreshProvider.notifier).bump();
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
                        child: Text(step.title,
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (!step.active) _tag('inactive'),
                  ]),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _tag(step.stepType.replaceAll('_', ' ')),
                    if (widget.character != null) _tag(widget.character!.name, icon: Icons.person),
                  ]),
                  if ((step.script ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(step.script!, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  if (step.stepType == kGuideStepTutorialObservation &&
                      step.detailOptions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('${step.detailOptions.length} tappable detail(s)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    OutlinedButton.icon(
                      onPressed: () => _showStepEditorDialog(
                        context,
                        ref,
                        characters: widget.characters,
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
                        await ref.read(gameGuideRepositoryProvider).deleteStep(step.id);
                        ref.read(gameGuideRefreshProvider.notifier).bump();
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
  required List<MissionCharacter> characters,
  GameGuideStep? step,
  int nextOrder = 1,
}) async {
  final title = TextEditingController(text: step?.title ?? '');
  final script = TextEditingController(text: step?.script ?? '');
  final sampleImageUrl = TextEditingController(text: step?.sampleImageUrl ?? '');
  final details = [...step?.detailOptions ?? const []];
  var stepType = step?.stepType ?? kGuideStepTutorialMessage;
  var characterId = step?.characterId;
  var active = step?.active ?? true;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(step == null ? 'Add Guide step' : 'Edit Guide step'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: title,
                  decoration: const InputDecoration(
                      labelText: 'Step title (admin-only label)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: stepType,
                decoration:
                    const InputDecoration(labelText: 'Step type', border: OutlineInputBorder()),
                items: [
                  for (final t in kGuideStepTypes)
                    DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' '))),
                ],
                onChanged: (v) => setState(() => stepType = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: characters.any((c) => c.id == characterId) ? characterId : null,
                decoration: const InputDecoration(
                    labelText: 'Character override (optional — defaults to the active Guide)',
                    border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— use the active Guide —')),
                  for (final c in characters) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => characterId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: script,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Script', border: OutlineInputBorder()),
              ),
              if (stepType == kGuideStepTutorialObservation) ...[
                const SizedBox(height: 20),
                const Text('Observation moment', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                    controller: sampleImageUrl,
                    decoration: const InputDecoration(
                        labelText: 'Sample photo URL', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(children: [
                  const Expanded(child: Text('Tappable details')),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => details.add(const GuideDetailOption(label: '', response: ''))),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add'),
                  ),
                ]),
                for (var i = 0; i < details.length; i++)
                  _DetailOptionEditorRow(
                    option: details[i],
                    onChanged: (o) => setState(() => details[i] = o),
                    onRemove: () => setState(() => details.removeAt(i)),
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
  final row = {
    'title': title.text.trim(),
    'step_type': stepType,
    'character_id': characterId,
    'script': script.text.trim().isEmpty ? null : script.text.trim(),
    'sample_image_url': sampleImageUrl.text.trim().isEmpty ? null : sampleImageUrl.text.trim(),
    'detail_options': details
        .where((d) => d.label.trim().isNotEmpty)
        .map((d) => d.toJson())
        .toList(),
    'active': active,
  };
  final repo = ref.read(gameGuideRepositoryProvider);
  if (step == null) {
    row['step_order'] = nextOrder;
    row['production_status'] = kGuideStatusDraft;
    await repo.createStep(row);
  } else {
    await repo.updateStep(step.id, row);
  }
  ref.read(gameGuideRefreshProvider.notifier).bump();
}

class _DetailOptionEditorRow extends StatefulWidget {
  const _DetailOptionEditorRow({required this.option, required this.onChanged, required this.onRemove});
  final GuideDetailOption option;
  final ValueChanged<GuideDetailOption> onChanged;
  final VoidCallback onRemove;

  @override
  State<_DetailOptionEditorRow> createState() => _DetailOptionEditorRowState();
}

class _DetailOptionEditorRowState extends State<_DetailOptionEditorRow> {
  late final _label = TextEditingController(text: widget.option.label);
  late final _response = TextEditingController(text: widget.option.response);

  void _emit() => widget.onChanged(GuideDetailOption(label: _label.text, response: _response.text));

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
                decoration: const InputDecoration(labelText: 'Tappable label', isDense: true),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: widget.onRemove,
            ),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: _response,
            onChanged: (_) => _emit(),
            decoration: const InputDecoration(labelText: 'Guide\'s response', isDense: true),
          ),
        ]),
      ),
    );
  }
}
