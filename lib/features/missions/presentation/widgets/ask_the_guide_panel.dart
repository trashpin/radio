import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/game_guide_repository.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// PROGRESSIVE GUIDE HINT SYSTEM — a reusable "🧭 Ask the Guide" panel for
/// any puzzle-answering screen. Deliberately dumb about WHAT it's helping
/// with: the caller (a mission's final puzzle, a stop's test of wits, or
/// any future puzzle type — they're all just [MissionPuzzle] rows already)
/// hands it exactly [hintLevels]/[answerRevealText] for THAT ONE puzzle,
/// so this widget is structurally incapable of leaking any other puzzle's
/// content, however it's used (spec: "It should NOT accidentally provide
/// information about Puzzle 8").
///
/// TEXT is always shown (spec: "Do not require the player to watch a
/// video while driving"). AUDIO is fetched via `discover-narration`'s
/// `subjectType: 'guide'` path — admin-authored hint text spoken verbatim
/// by the Guide's own ElevenLabs voice, the exact mechanism THE GUIDE's
/// own intro/tutorial lines already use. AVATAR, for this first version,
/// is the Guide's existing character portrait (not a freshly rendered
/// HeyGen video per hint line — see the shipped feature report for why).
class AskTheGuidePanel extends ConsumerStatefulWidget {
  const AskTheGuidePanel({
    super.key,
    required this.subjectId,
    required this.hintLevels,
    this.answerRevealText,
    required this.hintsUsed,
    required this.onRequestHint,
    this.onRevealAnswer,
  });

  /// Globally unique per puzzle — e.g. `'hint:${puzzle.id}'` — namespaces
  /// the narration cache per level via `subjectId:'$subjectId:$level'`.
  final String subjectId;
  final List<String> hintLevels;
  final String? answerRevealText;

  /// How many hint levels the player has already asked for (0 = none yet).
  final int hintsUsed;
  final VoidCallback onRequestHint;

  /// Null hides "Reveal Answer" entirely (e.g. the Treasure Hunt, which
  /// deliberately has no reveal tier — see `TreasureMapScreen`).
  final VoidCallback? onRevealAnswer;

  @override
  ConsumerState<AskTheGuidePanel> createState() => _AskTheGuidePanelState();
}

class _AskTheGuidePanelState extends ConsumerState<AskTheGuidePanel> {
  int? _spokenForLevel;
  bool _revealShown = false;

  Future<void> _speak(String text, int level) async {
    if (_spokenForLevel == level) return;
    _spokenForLevel = level;
    // Resolve the real Guide rather than trusting build()'s possibly-still-
    // loading snapshot — same fix as GuideIntroScreen._speak, otherwise a
    // hint requested the instant this panel first mounts could fall back
    // to the server's default voice instead of the Guide's own.
    final guide = await ref.read(activeGuideCharacterProvider.future);
    final result = await ref.read(missionNarrationServiceProvider).requestFor(
          subjectId: '${widget.subjectId}:$level',
          kind: 'guide',
          subjectType: 'guide',
          text: text,
          voiceId: guide?.voiceId,
        );
    await ref.read(missionAudioControllerProvider.notifier).play(
          title: guide?.name ?? 'The Guide',
          audioUrl: result?.audioUrl,
          spokenText: text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final guideAsync = ref.watch(activeGuideCharacterProvider);
    final guide = guideAsync.value;

    if (widget.hintsUsed == 0) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: widget.onRequestHint,
          icon: const Text('🧭'),
          label: const Text('Ask the Guide'),
        ),
      );
    }

    final levelIndex = (widget.hintsUsed - 1).clamp(0, widget.hintLevels.length - 1);
    final hintText =
        widget.hintLevels.isEmpty ? null : widget.hintLevels[levelIndex];
    final hasMoreHints = widget.hintsUsed < widget.hintLevels.length;
    final allHintsShown = widget.hintsUsed >= widget.hintLevels.length;
    final canReveal = allHintsShown &&
        widget.onRevealAnswer != null &&
        (widget.answerRevealText ?? '').trim().isNotEmpty;

    if (hintText != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _speak(hintText, levelIndex));
    }

    return GlassPanel(
      color: Colors.black.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: RD.panelAlt,
              backgroundImage:
                  (guide?.imageUrl ?? '').isNotEmpty ? NetworkImage(guide!.imageUrl!) : null,
              child: (guide?.imageUrl ?? '').isEmpty
                  ? const Icon(Icons.person_rounded, color: RD.textSecondary, size: 18)
                  : null,
            ),
            const SizedBox(width: RD.sm),
            Text(guide?.name ?? 'The Guide', style: RD.cardTitle.copyWith(color: Colors.white)),
          ]),
          if (hintText != null && !_revealShown) ...[
            const SizedBox(height: RD.sm),
            Text(hintText, style: RD.body.copyWith(color: Colors.white, fontSize: 14, height: 1.4)),
          ],
          if (_revealShown) ...[
            const SizedBox(height: RD.sm),
            Text(widget.answerRevealText!,
                style: RD.body.copyWith(color: RD.amber, fontSize: 14, height: 1.4)),
          ],
          const SizedBox(height: RD.sm),
          Wrap(spacing: RD.sm, runSpacing: RD.xs, children: [
            if (!_revealShown && hasMoreHints)
              OutlinedButton(
                onPressed: widget.onRequestHint,
                style: OutlinedButton.styleFrom(foregroundColor: RD.amber, side: const BorderSide(color: RD.amber)),
                child: Text(_nextHintLabel(widget.hintsUsed)),
              ),
            if (!_revealShown && canReveal)
              OutlinedButton(
                onPressed: () {
                  setState(() => _revealShown = true);
                  _speak(widget.answerRevealText!, -1);
                },
                style: OutlinedButton.styleFrom(foregroundColor: RD.textSecondary, side: const BorderSide(color: RD.textSecondary)),
                child: const Text('Reveal Answer'),
              ),
            if (_revealShown)
              FilledButton(
                onPressed: widget.onRevealAnswer,
                style: FilledButton.styleFrom(backgroundColor: RD.amber, foregroundColor: Colors.black),
                child: const Text('Continue'),
              ),
          ]),
        ],
      ),
    );
  }

  String _nextHintLabel(int hintsUsed) => switch (hintsUsed) {
        1 => 'Stronger Hint',
        _ => 'Guide Me',
      };
}
