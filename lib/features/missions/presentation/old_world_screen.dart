import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_puzzle.dart';
import 'package:explorer_os_mobile/features/missions/models/old_world.dart';
import 'package:explorer_os_mobile/features/missions/presentation/widgets/ask_the_guide_panel.dart';
import 'package:explorer_os_mobile/features/missions/presentation/widgets/character_video_hero.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

enum _Phase { discoveryFound, chapter, quiz, nextObjective }

/// "TODAY -> ENTER THE OLD WORLD" — the post-QR "next chapter" experience.
/// Scanning a valid QR doesn't just open an info page; it's a doorway into
/// a sequence: a brief DISCOVERY FOUND beat, the character's chapter
/// (video/narration/clue — unchanged from before this feature), an
/// OPTIONAL stop-level "test of wits" question (never blocks progression),
/// then YOUR NEXT OBJECTIVE before the existing journey map opens for the
/// next stop. [ActiveMissionController]'s single-active-geofence
/// transition already happened by the time any of this is on screen (see
/// [onQrScanned]/`_completeStop`) — this screen only decides what the
/// player sees next, never which geofence is active.
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
  MissionCharacter? _character;
  _Phase _phase = _Phase.discoveryFound;
  MissionPuzzle? _stopPuzzle;
  bool _puzzleChecked = false;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _speak(OldWorld world) async {
    if (_spoken) return;
    _spoken = true;

    // The brief "DISCOVERY FOUND" beat before the chapter reveals itself —
    // a doorway, not an instant info dump.
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _phase = _Phase.chapter);
    });

    // Facts are revealed the moment this Old World is shown — the player
    // may not know why yet (spec: "I was supposed to remember that").
    if (world.revealsFactKeys.isNotEmpty) {
      ref.read(activeMissionControllerProvider.notifier).markFactsRevealed(world.revealsFactKeys);
    }
    // CHARACTER -> VOICE ID: same character, same voice, whether they're
    // speaking during travel or here at the Old World reveal.
    final character =
        world.characterId == null ? null : await ref.read(missionRepositoryProvider).characterById(world.characterId!);
    if (mounted) setState(() => _character = character);

    if (!_puzzleChecked) {
      _puzzleChecked = true;
      final puzzle =
          world.stopId == null ? null : await ref.read(missionRepositoryProvider).puzzleForStop(world.stopId!);
      if (mounted) setState(() => _stopPuzzle = puzzle);
    }

    // "A NEW CHARACTER APPEARS" — when this reveal has an avatar video, it
    // already carries its own lip-synced narration audio, so the
    // audio-only TTS path below would talk over it (same rule
    // MissionIntroScreen follows for openingVideoUrl).
    if (world.hasCharacterVideo) return;

    final text = (world.narrationText ?? '').trim();
    if (text.isEmpty && (world.narrationAudioUrl ?? '').isEmpty) return;
    String? audioUrl = world.narrationAudioUrl;
    if ((audioUrl ?? '').isEmpty && text.isNotEmpty) {
      final result = await ref.read(missionNarrationServiceProvider).requestFor(
            subjectId: world.id,
            kind: 'old_world',
            text: text,
            voiceId: (character?.voiceId ?? '').trim().isNotEmpty ? character!.voiceId : world.voiceId,
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
            child: SafeArea(child: _buildPhase(context, world)),
          );
        },
      ),
    );
  }

  Widget _buildPhase(BuildContext context, OldWorld world) {
    switch (_phase) {
      case _Phase.discoveryFound:
        return const _DiscoveryFoundFlash();
      case _Phase.chapter:
        return _OldWorldContent(
          world: world,
          narratingCharacter: _character,
          onNext: () => _afterChapter(world),
        );
      case _Phase.quiz:
        return _QuizPhase(
          puzzle: _stopPuzzle!,
          onDone: (correct, hintsUsed, revealed) {
            if (correct && !revealed) {
              final awarded = (_stopPuzzle!.rewardXp - hintsUsed * _stopPuzzle!.hintXpPenalty)
                  .clamp(0, _stopPuzzle!.rewardXp);
              ref.read(activeMissionControllerProvider.notifier).awardBonusXp(awarded);
            }
            _afterQuiz(world);
          },
        );
      case _Phase.nextObjective:
        return _NextObjectivePhase(
          world: world,
          onBeginJourney: () => _onContinue(world),
        );
    }
  }

  void _afterChapter(OldWorld world) {
    if (_stopPuzzle != null) {
      setState(() => _phase = _Phase.quiz);
    } else {
      _afterQuiz(world);
    }
  }

  void _afterQuiz(OldWorld world) {
    final state = ref.read(activeMissionControllerProvider);
    // A genuine next stop to reveal only exists if the controller actually
    // advanced currentStop away from the one this Old World belongs to,
    // and the adventure isn't wrapping up right now.
    final hasNextStop = !state.missionComplete &&
        !state.hasPendingPuzzle &&
        state.currentStop != null &&
        state.currentStop!.id != world.stopId;
    if (hasNextStop) {
      setState(() => _phase = _Phase.nextObjective);
    } else {
      _onContinue(world);
    }
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

/// The brief "doorway" beat between a validated QR scan and the chapter
/// itself — makes the discovery feel like it caused something, rather
/// than instantly dumping the player into an info page.
class _DiscoveryFoundFlash extends StatelessWidget {
  const _DiscoveryFoundFlash();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: RD.amber, size: 48),
          const SizedBox(height: RD.md),
          Text('DISCOVERY FOUND',
              style: RD.tagline.copyWith(color: RD.amber, letterSpacing: 4, fontSize: 16)),
        ],
      ),
    );
  }
}

class _OldWorldContent extends StatelessWidget {
  const _OldWorldContent({required this.world, required this.onNext, this.narratingCharacter});
  final OldWorld world;
  final MissionCharacter? narratingCharacter;
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

        // "A NEW CHARACTER APPEARS" — the video (when this reveal has one)
        // is the headline moment, ahead of any supporting imagery. Falls
        // back to a prominent name/role/image block, then to the old
        // plain "Narrated by X" line when there's no character record at
        // all (free-text narratorName only).
        if (world.hasCharacterVideo) ...[
          CharacterVideoHero(videoUrl: world.characterVideoUrl!),
          const SizedBox(height: RD.lg),
        ] else if (narratingCharacter != null) ...[
          Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white12,
              backgroundImage: (narratingCharacter!.imageUrl ?? '').isNotEmpty
                  ? NetworkImage(narratingCharacter!.imageUrl!)
                  : null,
              child: (narratingCharacter!.imageUrl ?? '').isEmpty
                  ? const Icon(Icons.person_rounded, color: Colors.white54)
                  : null,
            ),
            const SizedBox(width: RD.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(narratingCharacter!.name,
                      style: RD.cardTitle.copyWith(color: Colors.white)),
                  if ((narratingCharacter!.role ?? '').isNotEmpty)
                    Text(narratingCharacter!.role!, style: RD.caption.copyWith(color: RD.amber)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: RD.lg),
        ] else if ((world.narratorName ?? '').isNotEmpty) ...[
          Row(children: [
            const Icon(Icons.record_voice_over_rounded, color: RD.amber, size: 18),
            const SizedBox(width: RD.xs),
            Text('Narrated by ${world.narratorName}',
                style: RD.caption.copyWith(color: Colors.white70)),
          ]),
          const SizedBox(height: RD.lg),
        ],

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

/// The optional "test of wits" — never blocks progression (spec: "the
/// adventure should NOT end" on a wrong answer). Reuses
/// [MissionPuzzle.checkAnswer]'s existing case-insensitive match, the same
/// mechanism the final puzzle already uses — just without the gate.
class _QuizPhase extends StatefulWidget {
  const _QuizPhase({required this.puzzle, required this.onDone});
  final MissionPuzzle puzzle;

  /// [hintsUsed]/[revealed] let the caller compute the same reduced-XP
  /// award `MissionPuzzleScreen` uses for the final puzzle — see
  /// `_afterQuiz`'s call to `awardBonusXp`.
  final void Function(bool correct, int hintsUsed, bool revealed) onDone;

  @override
  State<_QuizPhase> createState() => _QuizPhaseState();
}

class _QuizPhaseState extends State<_QuizPhase> {
  final _answer = TextEditingController();
  bool? _correct;
  int _hintsUsed = 0;
  bool _revealed = false;

  void _submit() {
    if (_correct != null) return;
    final correct = widget.puzzle.checkAnswer(_answer.text);
    setState(() => _correct = correct);
  }

  void _reveal() {
    if (_correct != null) return;
    setState(() {
      _correct = true;
      _revealed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        Text('WHAT DO YOU REMEMBER?', style: RD.tagline.copyWith(color: RD.amber, letterSpacing: 3)),
        const SizedBox(height: RD.lg),
        GlassPanel(
          color: Colors.black.withValues(alpha: 0.4),
          child: Text(widget.puzzle.prompt,
              style: RD.body.copyWith(color: Colors.white, fontSize: 16, height: 1.4)),
        ),
        const SizedBox(height: RD.lg),
        if (_correct == null) ...[
          TextField(
            controller: _answer,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              hintText: 'Your answer',
              hintStyle: const TextStyle(color: Colors.white38),
              border: OutlineInputBorder(borderRadius: RD.brLg, borderSide: BorderSide.none),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: RD.lg),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RD.amber, foregroundColor: Colors.black),
              onPressed: _submit,
              child: const Text('Answer', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          if (widget.puzzle.hintLevels.isNotEmpty) ...[
            const SizedBox(height: RD.lg),
            AskTheGuidePanel(
              subjectId: 'hint:${widget.puzzle.id}',
              hintLevels: widget.puzzle.hintLevels,
              answerRevealText: widget.puzzle.answerRevealText,
              hintsUsed: _hintsUsed,
              onRequestHint: () => setState(() => _hintsUsed++),
              onRevealAnswer:
                  (widget.puzzle.answerRevealText ?? '').trim().isEmpty ? null : _reveal,
            ),
          ],
        ] else ...[
          GlassPanel(
            color: (_correct! ? RD.green : Colors.orange).withValues(alpha: 0.15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_correct! ? 'YOU REMEMBERED.' : 'NOT QUITE.',
                    style: RD.sectionLabel.copyWith(color: _correct! ? RD.green : Colors.orange)),
                const SizedBox(height: RD.xs),
                Text(
                  _correct!
                      ? (widget.puzzle.successText ?? 'That detail mattered more than you knew.')
                      : (widget.puzzle.hint ?? 'That\'s alright — not every detail is easy to catch.'),
                  style: RD.body.copyWith(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: RD.lg),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RD.amber, foregroundColor: Colors.black),
              onPressed: () => widget.onDone(_correct!, _hintsUsed, _revealed),
              child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ],
    );
  }
}

/// "YOUR NEXT OBJECTIVE" — a non-spoiler teaser, then the existing journey
/// map's own destination/distance framing, reached only after the chapter
/// (and any test-of-wits question) is finished. Tapping BEGIN JOURNEY is
/// what actually returns to [MissionPlayerScreen]/the existing JourneyMap
/// — no new GPS/geofence system, no early reveal of the destination name
/// before this point.
class _NextObjectivePhase extends ConsumerWidget {
  const _NextObjectivePhase({required this.world, required this.onBeginJourney});
  final OldWorld world;
  final VoidCallback onBeginJourney;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextStop = ref.watch(activeMissionControllerProvider).currentStop;
    final playerLoc = ref.watch(gpsControllerProvider).location;
    final distanceMeters = (nextStop != null && playerLoc != null)
        ? GeoMath.distanceMeters(
            playerLoc.latitude, playerLoc.longitude, nextStop.latitude, nextStop.longitude)
        : null;

    return ListView(
      padding: const EdgeInsets.all(RD.lg),
      children: [
        Text('YOUR NEXT OBJECTIVE', style: RD.tagline.copyWith(color: RD.amber, letterSpacing: 3)),
        const SizedBox(height: RD.lg),
        if ((world.nextObjectiveText ?? '').isNotEmpty)
          GlassPanel(
            color: Colors.black.withValues(alpha: 0.4),
            child: Text(world.nextObjectiveText!,
                style: RD.body.copyWith(color: Colors.white, fontSize: 16, height: 1.5)),
          ),
        const SizedBox(height: RD.xxl),
        if (nextStop != null) ...[
          Text('NEXT DISCOVERY', style: RD.sectionLabel.copyWith(color: Colors.white54)),
          const SizedBox(height: RD.xs),
          Text(nextStop.title,
              style: RD.wordmark.copyWith(color: Colors.white, fontSize: 22)),
          if (distanceMeters != null) ...[
            const SizedBox(height: RD.xs),
            Text('${(distanceMeters / 1609.344).toStringAsFixed(1)} miles away',
                style: RD.caption.copyWith(color: Colors.white54)),
          ],
        ],
        const SizedBox(height: RD.xxl),
        SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RD.amber, foregroundColor: Colors.black),
            onPressed: onBeginJourney,
            child: const Text('BEGIN JOURNEY',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
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
