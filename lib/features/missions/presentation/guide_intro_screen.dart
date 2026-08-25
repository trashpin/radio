import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/explorer_profile_repository.dart';
import 'package:explorer_os_mobile/features/missions/data/game_guide_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/game_guide_step.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';
import 'package:explorer_os_mobile/features/missions/presentation/widgets/character_video_hero.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// THE GUIDE's permanent introduction to the game itself — NOT any one
/// adventure's story. Plays through [activeGuideStepsProvider] in order
/// (one `introduction`, several `tutorial_message`, one
/// `tutorial_observation`), then a closing "BECOME AN EXPLORER" beat. Every
/// word is admin-authored (Game Guide admin page) — nothing here is
/// hard-coded dialogue. Reused both for the first-time auto-launch from
/// Adventures and for REPLAY GUIDE.
class GuideIntroScreen extends ConsumerStatefulWidget {
  const GuideIntroScreen({super.key});

  @override
  ConsumerState<GuideIntroScreen> createState() => _GuideIntroScreenState();
}

class _GuideIntroScreenState extends ConsumerState<GuideIntroScreen> {
  int _index = 0;
  bool _markedStarted = false;
  String? _spokenForStepId;
  final Map<String, String> _observationResponse = {};

  Future<void> _speak(GameGuideStep step, MissionCharacter? character) async {
    if (_spokenForStepId == step.id) return;
    _spokenForStepId = step.id;

    if (!_markedStarted) {
      _markedStarted = true;
      ref.read(explorerProfileRepositoryProvider).markIntroductionStarted();
      ref.read(explorerProfileRefreshProvider.notifier).bump();
    }

    // The avatar video (when this step has one) already carries its own
    // lip-synced narration — the audio-only path below would talk over it,
    // same rule every other character-video scene in this app follows.
    if (step.hasAvatarVideo) return;

    final text = (step.script ?? '').trim();
    if (text.isEmpty && !step.hasAudio) return;
    String? audioUrl = step.audioUrl;
    if ((audioUrl ?? '').isEmpty && text.isNotEmpty) {
      final result = await ref.read(missionNarrationServiceProvider).requestFor(
            subjectId: 'guide-step:${step.id}',
            kind: 'guide',
            subjectType: 'guide',
            text: text,
            voiceId: (character?.voiceId ?? '').trim().isNotEmpty ? character!.voiceId : null,
          );
      audioUrl = result?.audioUrl;
    }
    await ref.read(missionAudioControllerProvider.notifier).play(
          title: character?.name ?? 'The Guide',
          audioUrl: audioUrl,
          spokenText: text,
        );
  }

  void _next() => setState(() => _index++);

  @override
  Widget build(BuildContext context) {
    final stepsAsync = ref.watch(activeGuideStepsProvider);
    final characterAsync = ref.watch(activeGuideCharacterProvider);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: stepsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: RD.green)),
          error: (e, _) =>
              Center(child: Text('Could not load your Guide.', style: RD.body)),
          data: (steps) {
            final character = characterAsync.value;
            if (steps.isEmpty) {
              // No Guide content configured yet — don't block the player.
              WidgetsBinding.instance.addPostFrameCallback((_) => _finish(activate: false));
              return const Center(child: CircularProgressIndicator(color: RD.green));
            }
            if (_index >= steps.length) {
              return _BecomeExplorerContent(character: character, onBecomeExplorer: () => _finish(activate: true));
            }
            final step = steps[_index];
            WidgetsBinding.instance.addPostFrameCallback((_) => _speak(step, character));
            return step.stepType == kGuideStepTutorialObservation
                ? _ObservationContent(
                    step: step,
                    character: character,
                    response: _observationResponse[step.id],
                    onPick: (label, response) =>
                        setState(() => _observationResponse[step.id] = response),
                    onNext: _next,
                  )
                : _StepContent(step: step, character: character, onNext: _next);
          },
        ),
      ),
    );
  }

  void _finish({required bool activate}) {
    if (activate) {
      ref.read(explorerProfileRepositoryProvider).markIntroductionCompleted();
      ref.read(explorerProfileRepositoryProvider).activateExplorer();
      ref.read(explorerProfileRefreshProvider.notifier).bump();
    }
    if (context.mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/missions');
      }
    }
  }
}

class _GuideHeader extends StatelessWidget {
  const _GuideHeader({required this.character});
  final MissionCharacter? character;

  @override
  Widget build(BuildContext context) {
    if (character == null) return const SizedBox.shrink();
    return Row(children: [
      CircleAvatar(
        radius: 24,
        backgroundColor: RD.panelAlt,
        backgroundImage:
            (character!.imageUrl ?? '').isNotEmpty ? NetworkImage(character!.imageUrl!) : null,
        child: (character!.imageUrl ?? '').isEmpty
            ? const Icon(Icons.person_rounded, color: RD.textSecondary)
            : null,
      ),
      const SizedBox(width: RD.md),
      Text(character!.name, style: RD.cardTitle.copyWith(color: Colors.white)),
    ]);
  }
}

class _StepContent extends StatelessWidget {
  const _StepContent({required this.step, required this.character, required this.onNext});
  final GameGuideStep step;
  final MissionCharacter? character;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        _GuideHeader(character: character),
        const SizedBox(height: RD.xl),
        if (step.hasAvatarVideo) ...[
          CharacterVideoHero(videoUrl: step.avatarVideoUrl!),
          const SizedBox(height: RD.xl),
        ],
        GlassPanel(
          padding: const EdgeInsets.all(RD.xl),
          child: Text(
            (step.script ?? '').trim().isEmpty ? '...' : step.script!.trim(),
            style: RD.body.copyWith(fontSize: 17, color: RD.textPrimary, height: 1.5),
          ),
        ),
        const SizedBox(height: RD.xxl),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RD.green, foregroundColor: RD.onGreen),
            onPressed: onNext,
            child: const Text('CONTINUE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
        ),
      ],
    );
  }
}

/// "WHAT DO YOU NOTICE?" — a short interactive moment, not a long tutorial
/// (spec). Detail chips (not pixel hotspots) are the smallest version that
/// satisfies "tap a visual detail."
class _ObservationContent extends StatelessWidget {
  const _ObservationContent({
    required this.step,
    required this.character,
    required this.response,
    required this.onPick,
    required this.onNext,
  });
  final GameGuideStep step;
  final MissionCharacter? character;
  final String? response;
  final void Function(String label, String response) onPick;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        _GuideHeader(character: character),
        const SizedBox(height: RD.xl),
        Text('WHAT DO YOU NOTICE?', style: RD.tagline.copyWith(color: RD.amber, letterSpacing: 3)),
        const SizedBox(height: RD.lg),
        if ((step.sampleImageUrl ?? '').isNotEmpty)
          ClipRRect(
            borderRadius: RD.brLg,
            child: Image.network(step.sampleImageUrl!, fit: BoxFit.cover, height: 200, width: double.infinity),
          )
        else
          Container(
            height: 200,
            decoration: BoxDecoration(color: RD.panelAlt, borderRadius: RD.brLg),
            child: const Center(child: Icon(Icons.photo_rounded, color: RD.textSecondary, size: 40)),
          ),
        const SizedBox(height: RD.lg),
        if (response == null)
          Wrap(spacing: RD.sm, runSpacing: RD.sm, children: [
            for (final option in step.detailOptions)
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: RD.textPrimary, side: const BorderSide(color: RD.green)),
                onPressed: () => onPick(option.label, option.response),
                child: Text(option.label),
              ),
          ])
        else ...[
          GlassPanel(
            padding: const EdgeInsets.all(RD.xl),
            child: Text(response!, style: RD.body.copyWith(fontSize: 16, color: RD.textPrimary, height: 1.5)),
          ),
          const SizedBox(height: RD.xxl),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RD.green, foregroundColor: RD.onGreen),
              onPressed: onNext,
              child: const Text('CONTINUE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
          ),
        ],
      ],
    );
  }
}

class _BecomeExplorerContent extends StatelessWidget {
  const _BecomeExplorerContent({required this.character, required this.onBecomeExplorer});
  final MissionCharacter? character;
  final VoidCallback onBecomeExplorer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(RD.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GuideHeader(character: character),
          const SizedBox(height: RD.xl),
          GlassPanel(
            padding: const EdgeInsets.all(RD.xl),
            child: Text(
              "There's only one thing left to do.",
              style: RD.body.copyWith(fontSize: 18, color: RD.textPrimary, height: 1.5),
            ),
          ),
          const SizedBox(height: RD.xxl),
          SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RD.amber, foregroundColor: Colors.black),
              onPressed: onBecomeExplorer,
              child: const Text('BECOME AN EXPLORER',
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}
