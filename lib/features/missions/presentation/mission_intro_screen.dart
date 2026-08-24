import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// The Adventure Introduction — shown the moment a player selects a
/// mission, BEFORE any map, GPS, or travel begins. The player should never
/// be dropped straight into a guided tour; they should first understand
/// what they're chasing, why, and that the story itself is part of the
/// puzzle. `BEGIN ADVENTURE` is what actually starts GPS tracking
/// ([MissionPlayerScreen]/`ActiveMissionController.startMission`) — this
/// screen only tells the story and sets expectations.
class MissionIntroScreen extends ConsumerStatefulWidget {
  const MissionIntroScreen({super.key, required this.missionId});
  final String missionId;

  @override
  ConsumerState<MissionIntroScreen> createState() => _MissionIntroScreenState();
}

class _MissionIntroScreenState extends ConsumerState<MissionIntroScreen> {
  bool _spoken = false;
  MissionCharacter? _character;

  Future<void> _speak(Mission mission) async {
    if (_spoken) return;
    _spoken = true;
    // CHARACTER -> VOICE ID: whoever speaks the introduction keeps that same
    // voice through every later scene that names them too (travel, arrival,
    // Old World) — see [ActiveMissionController._voiceIdFor].
    final character = mission.introCharacterId == null
        ? null
        : await ref.read(missionRepositoryProvider).characterById(mission.introCharacterId!);
    if (mounted) setState(() => _character = character);

    final text = (mission.openingNarrationText ?? '').trim();
    if (text.isEmpty && (mission.openingNarrationAudioUrl ?? '').isEmpty) return;
    String? audioUrl = mission.openingNarrationAudioUrl;
    if ((audioUrl ?? '').isEmpty && text.isNotEmpty) {
      final result = await ref.read(missionNarrationServiceProvider).requestFor(
            subjectId: 'opening:${mission.id}',
            kind: 'opening',
            text: text,
            voiceId: (character?.voiceId ?? '').trim().isNotEmpty ? character!.voiceId : null,
          );
      audioUrl = result?.audioUrl;
    }
    await ref.read(missionAudioControllerProvider.notifier).play(
          title: mission.title,
          audioUrl: audioUrl,
          spokenText: text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final missionAsync = ref.watch(missionByIdProvider(widget.missionId));
    return Scaffold(
      backgroundColor: RD.bg,
      body: missionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: RD.green)),
        error: (e, _) => Center(child: Text('Could not load this adventure.', style: RD.body)),
        data: (mission) {
          if (mission == null) {
            return Center(child: Text('Adventure not found.', style: RD.body));
          }
          WidgetsBinding.instance.addPostFrameCallback((_) => _speak(mission));
          return SafeArea(child: _IntroContent(mission: mission, character: _character));
        },
      ),
    );
  }
}

class _IntroContent extends StatelessWidget {
  const _IntroContent({required this.mission, this.character});
  final Mission mission;
  final MissionCharacter? character;

  static const _testsYourWits = [
    'Listen carefully',
    'Remember important details',
    'Explore your surroundings',
    'Notice things at locations',
    'Connect clues',
    'Solve puzzles',
    'Use information revealed during the story',
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: RD.textSecondary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ]),
        const SizedBox(height: RD.sm),
        Text(mission.title.toUpperCase(),
            style: RD.wordmark.copyWith(fontSize: 24, letterSpacing: 1)),
        if ((mission.category ?? '').isNotEmpty || (mission.difficulty ?? '').isNotEmpty) ...[
          const SizedBox(height: RD.sm),
          Wrap(spacing: RD.sm, children: [
            if ((mission.category ?? '').isNotEmpty) _pill(mission.category!),
            if ((mission.difficulty ?? '').isNotEmpty) _pill(mission.difficulty!),
          ]),
        ],
        const SizedBox(height: RD.xl),

        // The story itself — an immersive character moment, not a feature list.
        GlassPanel(
          padding: const EdgeInsets.all(RD.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (character != null) ...[
              Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: RD.panelAlt,
                  backgroundImage: (character!.imageUrl ?? '').isNotEmpty
                      ? NetworkImage(character!.imageUrl!)
                      : null,
                  child: (character!.imageUrl ?? '').isEmpty
                      ? const Icon(Icons.person_rounded, color: RD.textSecondary)
                      : null,
                ),
                const SizedBox(width: RD.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(character!.name, style: RD.cardTitle),
                      if ((character!.role ?? '').isNotEmpty)
                        Text(character!.role!, style: RD.caption.copyWith(color: RD.green)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: RD.md),
            ] else if ((mission.introCharacterName ?? '').isNotEmpty) ...[
              Row(children: [
                const Icon(Icons.record_voice_over_rounded, color: RD.green, size: 18),
                const SizedBox(width: RD.xs),
                Text(mission.introCharacterName!, style: RD.sectionLabel),
              ]),
              const SizedBox(height: RD.sm),
            ],
            Text(
              (mission.openingNarrationText ?? mission.description ?? '').trim().isEmpty
                  ? 'An adventure is waiting for you in Marion County.'
                  : (mission.openingNarrationText ?? mission.description)!,
              style: RD.body.copyWith(fontSize: 16, color: RD.textPrimary, height: 1.5),
            ),
          ]),
        ),

        if ((mission.missionBriefText ?? '').isNotEmpty) ...[
          const SizedBox(height: RD.xl),
          Text('YOUR MISSION', style: RD.sectionLabel),
          const SizedBox(height: RD.sm),
          Text(mission.missionBriefText!, style: RD.body.copyWith(fontSize: 14, height: 1.4)),
        ],

        const SizedBox(height: RD.xl),
        Text('THIS ADVENTURE WILL TEST YOUR WITS', style: RD.sectionLabel.copyWith(color: RD.amber)),
        const SizedBox(height: RD.sm),
        Text('You may need to:', style: RD.body),
        const SizedBox(height: RD.xs),
        for (final item in _testsYourWits)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.circle, size: 5, color: RD.textSecondary),
              const SizedBox(width: RD.sm),
              Expanded(child: Text(item, style: RD.body)),
            ]),
          ),

        const SizedBox(height: RD.xxl),
        SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RD.green, foregroundColor: RD.onGreen),
            onPressed: () =>
                context.pushReplacement(AppRoute.missionPlayer.missionPathFor(mission.id)),
            child: const Text('BEGIN ADVENTURE',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
        ),
        const SizedBox(height: RD.lg),
      ],
    );
  }

  Widget _pill(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: RD.sm, vertical: 4),
        decoration: BoxDecoration(
          color: RD.panelAlt,
          borderRadius: BorderRadius.circular(RD.rPill),
        ),
        child: Text(label, style: RD.caption),
      );
}
