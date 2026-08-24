import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_stop.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_story_step.dart';
import 'package:explorer_os_mobile/features/missions/services/heygen_avatar_service.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';
import 'package:explorer_os_mobile/features/missions/services/story_step_publisher.dart';

/// Admin -> Story Builder: build one adventure as an ordered sequence of
/// story steps (mission introduction/travel/approach/arrival/discovery/QR/
/// old world/clue/final reveal), each with its own character (and that
/// character's inherited ElevenLabs voice), script, presentation type, and
/// trigger. This is the authoring/production surface for
/// `mission_story_steps` (migration 0066) — PUBLISH writes a step's
/// produced content into the existing runtime table the live GPS/mission
/// player already reads (see `StoryStepPublisher`); nothing here is a
/// second GPS/trigger system.
class StoryBuilderPage extends ConsumerWidget {
  const StoryBuilderPage({super.key, required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stepsAsync = ref.watch(storyStepsForMissionProvider(mission.id));
    final stopsAsync = ref.watch(missionStopsProvider(mission.id));
    final charactersAsync = ref.watch(missionCharactersProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Story Builder — ${mission.title}')),
      body: stepsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AdminEmptyState(message: 'Could not load story steps: $e'),
        data: (steps) {
          final stops = stopsAsync.value ?? const [];
          final characters = charactersAsync.value ?? const [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdminPageHeader(
                title: mission.title,
                subtitle: '${steps.length} story step${steps.length == 1 ? '' : 's'} — '
                    'in the order the player experiences them.',
                actions: [
                  FilledButton.icon(
                    onPressed: () => showStoryStepEditorDialog(
                      context,
                      ref,
                      mission: mission,
                      stops: stops,
                      characters: characters,
                      nextOrder: steps.isEmpty ? 1 : steps.last.stepOrder + 1,
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Story Step'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (steps.isEmpty)
                const AdminEmptyState(
                  message: 'No story steps yet. Add one to start building this adventure.',
                  icon: Icons.auto_stories_outlined,
                )
              else
                for (var i = 0; i < steps.length; i++)
                  _StepRow(
                    step: steps[i],
                    index: i,
                    total: steps.length,
                    mission: mission,
                    stops: stops,
                    characters: characters,
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
    required this.stops,
    required this.characters,
    required this.character,
  });
  final MissionStoryStep step;
  final int index;
  final int total;
  final Mission mission;
  final List<MissionStop> stops;
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
    final voiceId = widget.character?.voiceId;
    final result = await ref.read(missionNarrationServiceProvider).requestFor(
          subjectId: 'step:${step.id}',
          kind: _kindFor(step.stepType),
          text: script,
          voiceId: voiceId,
          force: force,
        );
    if (result?.audioUrl != null) {
      final nextStatus = step.presentationType == kPresentationAvatarVideo
          ? kStatusAudioGenerated
          : kStatusReady;
      await ref.read(missionRepositoryProvider).updateStoryStep(step.id, {
        'audio_url': result!.audioUrl,
        'production_status': nextStatus,
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
          content: Text('Generate this step\'s voice first — the avatar lip-syncs to that '
              'exact audio, so it sounds the same as the character\'s other scenes.')));
      return;
    }
    if ((character?.heygenAvatarId ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(character == null
              ? 'Select a character with a HeyGen Avatar ID first.'
              : '${character.name} has no HeyGen Avatar ID assigned — add one in Character Manager.')));
      return;
    }

    setState(() => _busy = true);
    String? failure;
    final started = await ref.read(heyGenAvatarServiceProvider).generate(
          stepId: step.id,
          avatarId: character!.heygenAvatarId!,
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
          content: Text('Avatar video is rendering — this can take a few minutes. '
              'Use "Check Avatar Status" to check on it.')));
      setState(() => _busy = false);
    }
  }

  Future<void> _checkAvatarStatus() async {
    setState(() => _busy = true);
    final result = await ref.read(heyGenAvatarServiceProvider).checkStatus(widget.step.id);
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

  Future<void> _publish() async {
    setState(() => _busy = true);
    final result = await ref.read(storyStepPublisherProvider).publish(widget.step);
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    }
    ref.read(missionsRefreshProvider.notifier).bump();
  }

  Future<void> _move(int delta) async {
    final steps = await ref.read(missionRepositoryProvider).storyStepsForMission(widget.mission.id);
    final ordered = [...steps]..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
    final i = ordered.indexWhere((s) => s.id == widget.step.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= ordered.length) return;
    final a = ordered[i], b = ordered[j];
    final repo = ref.read(missionRepositoryProvider);
    await repo.updateStoryStep(a.id, {'step_order': b.stepOrder});
    await repo.updateStoryStep(b.id, {'step_order': a.stepOrder});
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
                        child: Text(step.title,
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                    _statusBadge(step.productionStatus),
                  ]),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _tag(step.stepType.replaceAll('_', ' ')),
                    if (widget.character != null) _tag(widget.character!.name, icon: Icons.person),
                    _tag(step.presentationType.replaceAll('_', ' '),
                        icon: step.presentationType == kPresentationAvatarVideo
                            ? Icons.videocam_outlined
                            : Icons.graphic_eq_rounded),
                    _tag(step.triggerType.replaceAll('_', ' '), icon: Icons.gps_fixed_rounded),
                  ]),
                  if ((step.script ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(step.script!, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    OutlinedButton.icon(
                      onPressed: () => showStoryStepEditorDialog(
                        context,
                        ref,
                        mission: widget.mission,
                        stops: widget.stops,
                        characters: widget.characters,
                        step: step,
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _generateVoice,
                      icon: const Icon(Icons.record_voice_over_rounded, size: 16),
                      label: Text(step.hasAudio ? 'Regenerate Voice' : 'Generate Voice'),
                    ),
                    if (step.hasAudio)
                      OutlinedButton.icon(
                        onPressed: _preview,
                        icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 16),
                        label: Text(_playing ? 'Stop' : 'Preview'),
                      ),
                    if (step.needsAvatar) ...[
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
                    ],
                    FilledButton.icon(
                      onPressed: _busy ? null : _publish,
                      icon: const Icon(Icons.publish_rounded, size: 16),
                      label: const Text('Publish'),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () async {
                        await ref.read(missionRepositoryProvider).deleteStoryStep(step.id);
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

  Widget _statusBadge(String status) {
    final Color color;
    switch (status) {
      case kStatusPublished:
        color = Colors.green;
      case kStatusReady:
      case kStatusVideoGenerated:
        color = Colors.teal;
      case kStatusAudioGenerated:
        color = Colors.blue;
      case kStatusScriptApproved:
        color = Colors.orange;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(status.replaceAll('_', ' ').toUpperCase(),
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

String _kindFor(String stepType) {
  switch (stepType) {
    case kStepTypeMissionIntroduction:
      return 'opening';
    case kStepTypeTravelStory:
      return 'travel';
    case kStepTypeApproachStory:
      return 'approach';
    case kStepTypeArrival:
      return 'arrival';
    case kStepTypeDiscovery:
    case kStepTypeQr:
    case kStepTypeOldWorld:
      return 'old_world';
    default:
      return 'story_step';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// The story step create/edit dialog. Every field is optional in the
/// schema (spec: "Do not assume every field must be used") — this editor
/// simply exposes all of them, since which ones matter depends entirely on
/// [MissionStoryStep.stepType].
Future<void> showStoryStepEditorDialog(
  BuildContext context,
  WidgetRef ref, {
  required Mission mission,
  required List<MissionStop> stops,
  required List<MissionCharacter> characters,
  MissionStoryStep? step,
  int nextOrder = 1,
}) async {
  final title = TextEditingController(text: step?.title ?? '');
  final script = TextEditingController(text: step?.script ?? '');
  final triggerDistanceMiles = TextEditingController(
      text: step?.triggerDistanceMeters == null
          ? ''
          : (step!.triggerDistanceMeters! / 1609.344).toStringAsFixed(2));
  final clueText = TextEditingController(text: step?.clueText ?? '');
  final questionText = TextEditingController(text: step?.questionText ?? '');
  final answerText = TextEditingController(text: step?.answerText ?? '');
  final xpReward = TextEditingController(text: '${step?.xpReward ?? 0}');
  var stepType = step?.stepType ?? kStepTypeTravelStory;
  var characterId = step?.characterId;
  var stopId = step?.stopId;
  var presentationType = step?.presentationType ?? kPresentationAudioOnly;
  var triggerType = step?.triggerType ?? kTriggerDistanceFromDestination;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(step == null ? 'Add story step' : 'Edit story step'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: title,
                  decoration:
                      const InputDecoration(labelText: 'Step title', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: stepType,
                decoration:
                    const InputDecoration(labelText: 'Step type', border: OutlineInputBorder()),
                items: [
                  for (final t in kMissionStoryStepTypes)
                    DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' '))),
                ],
                onChanged: (v) => setState(() => stepType = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: stops.any((s) => s.id == stopId) ? stopId : null,
                decoration: const InputDecoration(
                    labelText: 'Mission stop (optional — mission-level steps like the '
                        'introduction or final reveal need none)',
                    border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— none / mission-level —')),
                  for (final s in stops)
                    DropdownMenuItem(value: s.id, child: Text('${s.sequence}. ${s.title}')),
                ],
                onChanged: (v) => setState(() => stopId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: characters.any((c) => c.id == characterId) ? characterId : null,
                decoration:
                    const InputDecoration(labelText: 'Character', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— none —')),
                  for (final c in characters) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => characterId = v),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: presentationType,
                    decoration: const InputDecoration(
                        labelText: 'Presentation', border: OutlineInputBorder()),
                    items: [
                      for (final p in kMissionStepPresentationTypes)
                        DropdownMenuItem(value: p, child: Text(p.replaceAll('_', ' '))),
                    ],
                    onChanged: (v) => setState(() => presentationType = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: triggerType,
                    decoration:
                        const InputDecoration(labelText: 'Trigger', border: OutlineInputBorder()),
                    items: [
                      for (final t in kMissionStepTriggerTypes)
                        DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' '))),
                    ],
                    onChanged: (v) => setState(() => triggerType = v!),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: triggerDistanceMiles,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Trigger distance (miles, if distance/approach-based)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: script,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Script', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              const Text('Learning through gameplay (optional)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                  controller: clueText,
                  decoration:
                      const InputDecoration(labelText: 'Clue', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: questionText,
                  decoration:
                      const InputDecoration(labelText: 'Question', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: answerText,
                  decoration:
                      const InputDecoration(labelText: 'Answer', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                controller: xpReward,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'XP reward', border: OutlineInputBorder()),
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
    'stop_id': stopId,
    'title': title.text.trim(),
    'step_type': stepType,
    'character_id': characterId,
    'script': script.text.trim().isEmpty ? null : script.text.trim(),
    'presentation_type': presentationType,
    'trigger_type': triggerType,
    'trigger_distance_meters': miles == null ? null : miles * 1609.344,
    'clue_text': clueText.text.trim().isEmpty ? null : clueText.text.trim(),
    'question_text': questionText.text.trim().isEmpty ? null : questionText.text.trim(),
    'answer_text': answerText.text.trim().isEmpty ? null : answerText.text.trim(),
    'xp_reward': int.tryParse(xpReward.text.trim()) ?? 0,
  };
  final repo = ref.read(missionRepositoryProvider);
  if (step == null) {
    row['step_order'] = nextOrder;
    row['production_status'] = kStatusDraft;
    await repo.createStoryStep(row);
  } else {
    await repo.updateStoryStep(step.id, row);
  }
  ref.read(missionsRefreshProvider.notifier).bump();
}
