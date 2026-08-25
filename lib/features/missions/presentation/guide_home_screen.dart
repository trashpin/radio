import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/game_guide_repository.dart';
import 'package:explorer_os_mobile/features/missions/data/guide_step_provider.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/data/treasure_map_provider.dart';
import 'package:explorer_os_mobile/features/missions/models/guide_step.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_puzzle.dart';
import 'package:explorer_os_mobile/features/missions/presentation/treasure_map_panel_screen.dart';
import 'package:explorer_os_mobile/features/missions/presentation/widgets/ask_the_guide_panel.dart';
import 'package:explorer_os_mobile/features/missions/presentation/widgets/character_video_hero.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';
import 'package:explorer_os_mobile/features/missions/services/safe_travel.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// GUIDE — the permanent fourth primary tab. The Guide's per-adventure
/// companion role, distinct from THE GUIDE's one-time onboarding
/// (`GuideIntroScreen`, unrelated/untouched). Everything here is a PULL
/// model (spec's own "the player can open the clue when appropriate"
/// philosophy, already established by the Treasure Map): opening this
/// screen computes the next relevant [GuideStep] fresh via
/// [nextGuideStepProvider] — nothing auto-interrupts the player.
class GuideHomeScreen extends ConsumerWidget {
  const GuideHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionState = ref.watch(activeMissionControllerProvider);
    final mission = missionState.mission;

    return Scaffold(
      backgroundColor: RD.bg,
      appBar: AppBar(
        backgroundColor: RD.bg,
        foregroundColor: RD.textPrimary,
        title: const Text('Your Guide'),
        actions: [
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => context.push(AppRoute.more.path),
          ),
        ],
      ),
      body: SafeArea(
        child: mission == null
            ? const _NoAdventureContent()
            : _ActiveGuideContent(missionId: mission.id, missionState: missionState),
      ),
    );
  }
}

class _NoAdventureContent extends StatelessWidget {
  const _NoAdventureContent();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search_rounded, size: 48, color: RD.textSecondary),
            const SizedBox(height: RD.md),
            Text('Start an adventure to meet your Guide.',
                style: RD.body, textAlign: TextAlign.center),
            const SizedBox(height: RD.lg),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RD.green, foregroundColor: RD.onGreen),
              onPressed: () => context.go(AppRoute.missionsHome.path),
              child: const Text('Find an Adventure'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveGuideContent extends ConsumerStatefulWidget {
  const _ActiveGuideContent({required this.missionId, required this.missionState});
  final String missionId;
  final ActiveMissionState missionState;

  @override
  ConsumerState<_ActiveGuideContent> createState() => _ActiveGuideContentState();
}

class _ActiveGuideContentState extends ConsumerState<_ActiveGuideContent> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final guideAsync = ref.watch(activeGuideCharacterProvider);
    final stepAsync = ref.watch(nextGuideStepProvider(widget.missionId));
    final treasureMapAsync = ref.watch(treasureMapProvider(widget.missionId));
    final guide = guideAsync.value;

    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: RD.panelAlt,
            backgroundImage:
                (guide?.imageUrl ?? '').isNotEmpty ? NetworkImage(guide!.imageUrl!) : null,
            child: (guide?.imageUrl ?? '').isEmpty
                ? const Icon(Icons.person_rounded, color: RD.textSecondary)
                : null,
          ),
          const SizedBox(width: RD.md),
          Text(guide?.name ?? 'The Guide', style: RD.cardTitle.copyWith(color: Colors.white)),
        ]),
        const SizedBox(height: RD.lg),
        stepAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: RD.green)),
          error: (e, _) => Text('Could not reach your Guide right now.', style: RD.body),
          data: (step) => step == null
              ? GlassPanel(
                  child: Text(
                    "Nothing new right now — keep exploring. I'll have more to say soon.",
                    style: RD.body.copyWith(color: Colors.white70),
                  ),
                )
              : GuideStepContent(
                  step: step,
                  guide: guide,
                  onDone: () {
                    ref.read(activeMissionControllerProvider.notifier).markGuideStepShown(step.id);
                    _refresh();
                  },
                ),
        ),
        if (widget.missionState.hasPendingPuzzle) ...[
          const SizedBox(height: RD.lg),
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoute.missionPuzzle.path),
            style: OutlinedButton.styleFrom(foregroundColor: RD.amber, side: const BorderSide(color: RD.amber)),
            icon: const Text('🧭'),
            label: const Text('Ask the Guide'),
          ),
        ],
        const SizedBox(height: RD.xxl),
        treasureMapAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (data) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AVAILABLE CLUES', style: RD.tagline.copyWith(color: RD.amber, letterSpacing: 3)),
            const SizedBox(height: RD.md),
            if (data.clues.isEmpty)
              Text('No clues discovered yet.', style: RD.caption.copyWith(color: RD.textSecondary))
            else
              Wrap(spacing: RD.sm, runSpacing: RD.sm, children: [
                for (final clue in data.clues)
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome_rounded, size: 16, color: RD.amber),
                    label: Text(clue.title, overflow: TextOverflow.ellipsis),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => ClueViewerSheet(clue: clue),
                    ),
                  ),
              ]),
            const SizedBox(height: RD.lg),
            OutlinedButton.icon(
              onPressed: () => context.push(
                  AppRoute.missionDiscoveries.missionDiscoveriesPathFor(widget.missionId)),
              icon: const Icon(Icons.map_outlined),
              label: const Text('My Clues & Treasure Map'),
            ),
          ]),
        ),
      ],
    );
  }
}

/// Renders one [GuideStep] by [GuideStep.contentType]. Reuses every
/// existing media/interaction widget in this app — no new player, no new
/// answer-checking, no new hint system.
class GuideStepContent extends ConsumerStatefulWidget {
  const GuideStepContent({super.key, required this.step, required this.guide, required this.onDone});
  final GuideStep step;
  final MissionCharacter? guide;
  final VoidCallback onDone;

  @override
  ConsumerState<GuideStepContent> createState() => _GuideStepContentState();
}

class _GuideStepContentState extends ConsumerState<GuideStepContent> {
  bool _spoken = false;
  MissionPuzzle? _puzzle;
  bool _loadingPuzzle = false;
  final _answer = TextEditingController();
  bool? _puzzleCorrect;
  int _hintsUsed = 0;
  String? _choiceResponse;
  bool _showTranscript = false;

  @override
  void initState() {
    super.initState();
    final puzzleId = widget.step.puzzleId;
    if (puzzleId != null &&
        (widget.step.contentType == kGuideContentRiddle ||
            widget.step.contentType == kGuideContentQuestion)) {
      _loadingPuzzle = true;
      ref.read(missionRepositoryProvider).puzzleById(puzzleId).then((p) {
        if (mounted) {
          setState(() {
            _puzzle = p;
            _loadingPuzzle = false;
          });
        }
      });
    }
  }

  Future<void> _speak() async {
    if (_spoken) return;
    _spoken = true;
    if (widget.step.hasAvatarVideo) return;
    final text = (widget.step.script ?? '').trim();
    if (text.isEmpty && !widget.step.hasAudio) return;
    String? audioUrl = widget.step.audioUrl;
    if ((audioUrl ?? '').isEmpty && text.isNotEmpty) {
      final result = await ref.read(missionNarrationServiceProvider).requestFor(
            subjectId: 'guide-step-content:${widget.step.id}',
            kind: 'guide',
            subjectType: 'guide',
            text: text,
            voiceId: widget.guide?.voiceId,
          );
      audioUrl = result?.audioUrl;
    }
    await ref.read(missionAudioControllerProvider.notifier).play(
          title: widget.guide?.name ?? 'The Guide',
          audioUrl: audioUrl,
          spokenText: text,
        );
  }

  void _submitPuzzle() {
    if (_puzzle == null || _puzzleCorrect != null) return;
    final correct = _puzzle!.checkAnswer(_answer.text);
    setState(() => _puzzleCorrect = correct);
    if (correct) {
      final awarded =
          (_puzzle!.rewardXp - _hintsUsed * _puzzle!.hintXpPenalty).clamp(0, _puzzle!.rewardXp);
      ref.read(activeMissionControllerProvider.notifier)
        ..markPuzzleSolved(_puzzle!.id)
        ..awardBonusXp(awarded);
    }
  }

  /// Whether [GuideStep.script] is "what the Guide just said" (spoken via
  /// the video/audio above, so showing it again by default would be the
  /// exact duplicate the spec asks to remove — kept only behind VIEW
  /// TRANSCRIPT) as opposed to a written prompt that IS the activity
  /// itself (PONDER/CLUE, always visible — there's nothing to duplicate,
  /// it's the only copy of a question the player needs to keep re-reading).
  bool get _scriptIsSpokenDialogue =>
      widget.step.contentType != kGuideContentPonder && widget.step.contentType != kGuideContentClue;

  @override
  Widget build(BuildContext context) {
    final speed = ref.watch(gpsControllerProvider).location?.speedMps;
    final moving = isMovingTooFastForInteraction(speed);
    // AUDIO, and TALK when it has no avatar video, are always safe while
    // driving (spec: "audio narration, audio clues, spoken reminders" —
    // never video). A TALK step WITH an avatar video needs the player
    // safely stopped, same as VIDEO.
    final audioOnly = widget.step.contentType == kGuideContentAudio ||
        (widget.step.contentType == kGuideContentTalk && !widget.step.hasAvatarVideo);
    final script = (widget.step.script ?? '').trim();
    final hasTranscript = script.isNotEmpty && _scriptIsSpokenDialogue;

    WidgetsBinding.instance.addPostFrameCallback((_) => _speak());

    final contentPanel = (!audioOnly && moving) ? null : _buildContentPanel(script);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. GUIDE VIDEO AT THE TOP — the primary communication. No caption
        // underneath by default (spec: "Do not display a duplicate text
        // version of what the Guide just said underneath the video").
        _GuideVideoBlock(step: widget.step, guide: widget.guide),
        if (hasTranscript) ...[
          const SizedBox(height: RD.xs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _showTranscript = !_showTranscript),
              icon: Icon(_showTranscript ? Icons.expand_less_rounded : Icons.subtitles_outlined,
                  size: 16, color: RD.textSecondary),
              label: Text(_showTranscript ? 'Hide Transcript' : 'View Transcript',
                  style: RD.caption.copyWith(color: RD.textSecondary)),
            ),
          ),
          if (_showTranscript)
            Padding(
              padding: const EdgeInsets.only(bottom: RD.sm),
              child: Text(script,
                  style: RD.body.copyWith(color: Colors.white70, fontSize: 14, height: 1.4)),
            ),
        ],
        if (!audioOnly && moving) ...[
          const SizedBox(height: RD.md),
          GlassPanel(
            color: RD.amber.withValues(alpha: 0.12),
            child: Row(children: [
              const Icon(Icons.directions_car_filled_rounded, color: RD.amber),
              const SizedBox(width: RD.sm),
              Expanded(
                child: Text(
                  "A clue is waiting for you. We'll show it when you arrive or when you're safely stopped.",
                  style: RD.body.copyWith(color: Colors.white),
                ),
              ),
            ]),
          ),
        ] else if (contentPanel != null) ...[
          // 2. CLUE / ACTIVITY PRESENTED BELOW — a visually distinct block,
          // separate from the Guide's own video (spec: "The Guide video and
          // the clue are two separate components").
          const SizedBox(height: RD.md),
          Text(_contentLabel(), style: RD.tagline.copyWith(color: RD.amber, letterSpacing: 2, fontSize: 12)),
          const SizedBox(height: RD.sm),
          GlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: contentPanel)),
        ],
        const SizedBox(height: RD.lg),
        // 3. ACTION BUTTON
        if (_showContinueButton(moving, audioOnly))
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RD.green, foregroundColor: RD.onGreen),
              onPressed: _onActionPressed,
              child: Text(_actionLabel(), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  String _contentLabel() => switch (widget.step.contentType) {
        kGuideContentImage || kGuideContentInspect => 'PHOTO CLUE',
        kGuideContentAudio => 'AUDIO CLUE',
        kGuideContentPonder => 'PONDER',
        kGuideContentRiddle => 'RIDDLE',
        kGuideContentQuestion => 'QUESTION',
        kGuideContentMap || kGuideContentDiscovery => 'MAP DISCOVERY',
        kGuideContentChoice => 'CHOICE',
        _ => 'CLUE',
      };

  // Once a riddle/question/choice's own inline interaction is already
  // complete, the bottom button always just means "move on" — only
  // IMAGE/INSPECT and MAP/DISCOVERY have no inline interaction of their
  // own, so the bottom button IS their first and only action there.
  String _actionLabel() => switch (widget.step.contentType) {
        kGuideContentImage || kGuideContentInspect => 'INSPECT',
        kGuideContentMap || kGuideContentDiscovery => 'VIEW MAP',
        _ => 'CONTINUE',
      };

  void _onActionPressed() {
    if (widget.step.contentType == kGuideContentMap ||
        widget.step.contentType == kGuideContentDiscovery) {
      context.push(AppRoute.missionDiscoveries.missionDiscoveriesPathFor(widget.step.missionId));
    }
    widget.onDone();
  }

  bool _showContinueButton(bool moving, bool audioOnly) {
    if (!audioOnly && moving) return false;
    switch (widget.step.contentType) {
      case kGuideContentRiddle:
      case kGuideContentQuestion:
        return _puzzleCorrect == true;
      case kGuideContentChoice:
        return _choiceResponse != null;
      default:
        return true;
    }
  }

  /// The "CLUE / ACTIVITY" block underneath the Guide's video — a visually
  /// distinct panel (spec: "The Guide video and the clue are two separate
  /// components"). Returns null for a bare TALK/VIDEO/simple message with
  /// nothing to show beyond the video itself (spec's "SIMPLE GUIDE
  /// MOMENTS": just the video and CONTINUE, "do not create an unnecessary
  /// text card").
  List<Widget>? _buildContentPanel(String script) {
    switch (widget.step.contentType) {
      case kGuideContentTalk:
      case kGuideContentVideo:
        return null;
      case kGuideContentImage:
      case kGuideContentInspect:
        if ((widget.step.imageUrl ?? '').isEmpty) return null;
        return [
          ClipRRect(
            borderRadius: RD.brLg,
            child: InteractiveViewer(maxScale: 4, child: Image.network(widget.step.imageUrl!)),
          ),
        ];
      case kGuideContentAudio:
        return [_AudioControls(step: widget.step, guide: widget.guide)];
      case kGuideContentPonder:
        return [
          if (script.isNotEmpty) ...[
            Text(script, style: RD.body.copyWith(color: Colors.white, fontSize: 16, height: 1.4)),
            const SizedBox(height: RD.md),
          ],
          Wrap(spacing: RD.sm, runSpacing: RD.sm, children: [
            OutlinedButton(onPressed: () {}, child: const Text('I HAVE AN IDEA')),
            OutlinedButton(onPressed: () {}, child: const Text("I'M NOT SURE")),
          ]),
        ];
      case kGuideContentRiddle:
      case kGuideContentQuestion:
        if (_loadingPuzzle) return [const CircularProgressIndicator(color: RD.green)];
        if (_puzzle == null) return [Text('No question configured.', style: RD.caption)];
        return [
          Text(_puzzle!.prompt, style: RD.body.copyWith(color: Colors.white, fontSize: 16)),
          const SizedBox(height: RD.md),
          if (_puzzleCorrect != true) ...[
            TextField(
              controller: _answer,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                hintText: 'Your answer',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: RD.brMd, borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _submitPuzzle(),
            ),
            const SizedBox(height: RD.sm),
            SizedBox(
              height: 44,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: RD.amber, foregroundColor: Colors.black),
                onPressed: _submitPuzzle,
                child: const Text('Answer'),
              ),
            ),
            const SizedBox(height: RD.md),
            if (_puzzle!.hintLevels.isNotEmpty)
              AskTheGuidePanel(
                subjectId: 'hint:${_puzzle!.id}',
                hintLevels: _puzzle!.hintLevels,
                answerRevealText: _puzzle!.answerRevealText,
                hintsUsed: _hintsUsed,
                onRequestHint: () => setState(() => _hintsUsed++),
                onRevealAnswer: (_puzzle!.answerRevealText ?? '').trim().isEmpty
                    ? null
                    : () {
                        ref.read(activeMissionControllerProvider.notifier).markPuzzleSolved(_puzzle!.id);
                        setState(() => _puzzleCorrect = true);
                      },
              ),
          ] else
            Text(_puzzle!.successText ?? 'You remembered.',
                style: RD.body.copyWith(color: RD.green)),
        ];
      case kGuideContentClue:
        if (script.isEmpty) return null;
        return [Text(script, style: RD.body.copyWith(color: Colors.white, fontSize: 15, height: 1.5))];
      case kGuideContentMap:
      case kGuideContentDiscovery:
        return [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: RD.amber),
            const SizedBox(width: RD.sm),
            Text('NEW MAP PIECE', style: RD.cardTitle.copyWith(color: Colors.white)),
          ]),
        ];
      case kGuideContentChoice:
        if (_choiceResponse != null) {
          return [Text(_choiceResponse!, style: RD.body.copyWith(color: Colors.white))];
        }
        return [
          Wrap(spacing: RD.sm, runSpacing: RD.sm, children: [
            for (final option in widget.step.choiceOptions)
              OutlinedButton(
                onPressed: () => setState(() => _choiceResponse = option.response),
                child: Text(option.label),
              ),
          ]),
        ];
      default:
        return null;
    }
  }
}

/// GUIDE VIDEO AT THE TOP — the primary communication (spec). Falls back
/// to the Guide's static portrait, still visually prominent, when this
/// step has no avatar video of its own (generating one per step is
/// deliberately out of scope — see the shipped feature reports for why).
class _GuideVideoBlock extends StatelessWidget {
  const _GuideVideoBlock({required this.step, required this.guide});
  final GuideStep step;
  final MissionCharacter? guide;

  @override
  Widget build(BuildContext context) {
    if (step.hasAvatarVideo) {
      return CharacterVideoHero(videoUrl: step.avatarVideoUrl!);
    }
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: RD.brLg,
        child: Container(
          color: RD.panelAlt,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 56,
                  backgroundColor: RD.panel,
                  backgroundImage:
                      (guide?.imageUrl ?? '').isNotEmpty ? NetworkImage(guide!.imageUrl!) : null,
                  child: (guide?.imageUrl ?? '').isEmpty
                      ? const Icon(Icons.person_rounded, color: RD.textSecondary, size: 48)
                      : null,
                ),
                const SizedBox(height: RD.md),
                Text(guide?.name ?? 'The Guide', style: RD.cardTitle.copyWith(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioControls extends ConsumerWidget {
  const _AudioControls({required this.step, required this.guide});
  final GuideStep step;
  final MissionCharacter? guide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioState = ref.watch(missionAudioControllerProvider);
    final playing = audioState.isActive && audioState.title == (guide?.name ?? 'The Guide');
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: RD.amber, foregroundColor: Colors.black),
        onPressed: () {
          final controller = ref.read(missionAudioControllerProvider.notifier);
          if (playing) {
            controller.replay(guide?.name ?? 'The Guide');
          } else {
            controller.play(
                title: guide?.name ?? 'The Guide', audioUrl: step.audioUrl, spokenText: step.script);
          }
        },
        icon: Icon(playing ? Icons.replay_rounded : Icons.play_arrow_rounded),
        label: Text(playing ? 'PLAY AGAIN' : 'PLAY'),
      ),
    );
  }
}
