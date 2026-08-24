import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/old_world.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "TODAY -> ENTER THE OLD WORLD" (spec Phase 5). The transition itself is a
/// simple fade/scale reveal — special without needing new animation
/// infrastructure. Plays the Old World's narration through the SAME
/// duck/resume audio mechanism every other mission beat uses.
class OldWorldScreen extends ConsumerStatefulWidget {
  const OldWorldScreen({super.key, required this.oldWorldId, this.missionComplete = false});
  final String oldWorldId;
  final bool missionComplete;

  @override
  ConsumerState<OldWorldScreen> createState() => _OldWorldScreenState();
}

class _OldWorldScreenState extends ConsumerState<OldWorldScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  bool _spoken = false;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _speak(OldWorld world) async {
    if (_spoken) return;
    _spoken = true;
    // Facts are revealed the moment this Old World is shown — the player
    // may not know why yet (spec: "I was supposed to remember that").
    if (world.revealsFactKeys.isNotEmpty) {
      ref.read(activeMissionControllerProvider.notifier).markFactsRevealed(world.revealsFactKeys);
    }
    final text = (world.narrationText ?? '').trim();
    if (text.isEmpty && (world.narrationAudioUrl ?? '').isEmpty) return;
    String? audioUrl = world.narrationAudioUrl;
    if ((audioUrl ?? '').isEmpty && text.isNotEmpty) {
      final result = await ref.read(missionNarrationServiceProvider).requestFor(
            subjectId: world.id,
            kind: 'old_world',
            text: text,
            voiceId: world.voiceId,
          );
      audioUrl = result?.audioUrl;
    }
    await ref.read(missionAudioControllerProvider.notifier).play(
          title: world.title,
          audioUrl: audioUrl,
          spokenText: text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final worldAsync = ref.watch(oldWorldByIdProvider(widget.oldWorldId));
    return Scaffold(
      backgroundColor: const Color(0xFF1B140A), // a warm, aged "old world" tone
      body: worldAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: RD.amber)),
        error: (e, _) => Center(
          child: Text('Could not open the Old World.', style: RD.body.copyWith(color: Colors.white70)),
        ),
        data: (world) {
          if (world == null) {
            return Center(
              child: Text('This discovery could not be found.',
                  style: RD.body.copyWith(color: Colors.white70)),
            );
          }
          WidgetsBinding.instance.addPostFrameCallback((_) => _speak(world));
          return FadeTransition(
            opacity: _anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(
                  CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic)),
              child: SafeArea(child: _OldWorldContent(world: world, onNext: () => _onContinue(world))),
            ),
          );
        },
      ),
    );
  }

  void _onContinue(OldWorld world) {
    // A pending final puzzle always takes priority over the plain
    // missionComplete flag passed in via the route — the mission isn't
    // actually complete until the puzzle is solved (see
    // ActiveMissionController._checkFinalPuzzleOrComplete).
    final hasPendingPuzzle = ref.read(activeMissionControllerProvider).hasPendingPuzzle;
    if (hasPendingPuzzle) {
      context.pushReplacement(AppRoute.missionPuzzle.path);
    } else if (widget.missionComplete) {
      context.pushReplacement(AppRoute.missionComplete.path);
    } else {
      context.pop();
    }
  }
}

class _OldWorldContent extends StatelessWidget {
  const _OldWorldContent({required this.world, required this.onNext});
  final OldWorld world;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        Text('ENTER THE OLD WORLD', style: RD.tagline.copyWith(color: RD.amber, letterSpacing: 4)),
        const SizedBox(height: RD.sm),
        Text(world.title,
            style: RD.wordmark.copyWith(color: Colors.white, fontSize: 26, letterSpacing: 0.5)),
        if ((world.historicalPeriod ?? '').isNotEmpty) ...[
          const SizedBox(height: RD.xs),
          Text(world.historicalPeriod!, style: RD.body.copyWith(color: Colors.white60)),
        ],
        const SizedBox(height: RD.sm),
        _FictionalBadge(isFictional: world.isFictional),
        const SizedBox(height: RD.lg),
        if ((world.heroImageUrl ?? '').isNotEmpty)
          ClipRRect(
            borderRadius: RD.brLg,
            child: Image.network(world.heroImageUrl!, fit: BoxFit.cover, height: 200, width: double.infinity),
          ),
        if ((world.historicalMapImageUrl ?? '').isNotEmpty) ...[
          const SizedBox(height: RD.md),
          ClipRRect(
            borderRadius: RD.brLg,
            child: Image.network(world.historicalMapImageUrl!, fit: BoxFit.cover),
          ),
        ],
        if ((world.narratorName ?? '').isNotEmpty) ...[
          const SizedBox(height: RD.lg),
          Row(children: [
            const Icon(Icons.record_voice_over_rounded, color: RD.amber, size: 18),
            const SizedBox(width: RD.xs),
            Text('Narrated by ${world.narratorName}',
                style: RD.caption.copyWith(color: Colors.white70)),
          ]),
        ],
        if ((world.narrationText ?? '').isNotEmpty) ...[
          const SizedBox(height: RD.md),
          Text(world.narrationText!, style: RD.body.copyWith(color: Colors.white.withValues(alpha: 0.9), fontSize: 15, height: 1.5)),
        ],
        if (world.characters.isNotEmpty) ...[
          const SizedBox(height: RD.lg),
          Text('CHARACTERS', style: RD.sectionLabel.copyWith(color: RD.amber)),
          const SizedBox(height: RD.sm),
          for (final c in world.characters) _CharacterTile(character: c),
        ],
        if (world.hasClue) ...[
          const SizedBox(height: RD.lg),
          GlassPanel(
            color: Colors.black.withValues(alpha: 0.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: const [
                  Icon(Icons.auto_awesome_rounded, color: RD.amber, size: 18),
                  SizedBox(width: RD.xs),
                  Text('YOUR CLUE', style: RD.sectionLabel),
                ]),
                const SizedBox(height: RD.xs),
                Text(world.clueText!, style: RD.body.copyWith(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ],
        const SizedBox(height: RD.xxl),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RD.amber, foregroundColor: Colors.black),
            onPressed: onNext,
            child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

class _FictionalBadge extends StatelessWidget {
  const _FictionalBadge({required this.isFictional});
  final bool isFictional;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: RD.sm, vertical: 4),
      decoration: BoxDecoration(
        color: (isFictional ? Colors.purple : RD.green).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(RD.rPill),
        border: Border.all(color: isFictional ? Colors.purpleAccent : RD.green),
      ),
      child: Text(
        isFictional ? 'FICTIONAL STORY' : 'VERIFIED HISTORY',
        style: RD.badge.copyWith(color: isFictional ? Colors.purpleAccent : RD.green),
      ),
    );
  }
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({required this.character});
  final OldWorldCharacter character;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RD.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: RD.panelAlt,
            backgroundImage:
                (character.imageUrl ?? '').isNotEmpty ? NetworkImage(character.imageUrl!) : null,
            child: (character.imageUrl ?? '').isEmpty
                ? const Icon(Icons.person_rounded, color: Colors.white54)
                : null,
          ),
          const SizedBox(width: RD.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(character.name,
                    style: RD.cardTitle.copyWith(color: Colors.white)),
                if ((character.description ?? '').isNotEmpty)
                  Text(character.description!,
                      style: RD.caption.copyWith(color: Colors.white60)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
