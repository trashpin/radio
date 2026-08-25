import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_puzzle.dart';
import 'package:explorer_os_mobile/features/missions/presentation/widgets/ask_the_guide_panel.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';

/// A test of attention/reasoning (spec: MEMORY/OBSERVATION/DEDUCTION/
/// HISTORY/CODE/CONNECTION/DIRECTION). Today, always the mission's final
/// puzzle ([ActiveMissionState.pendingPuzzle]) — answer checking is a
/// simple, honest string match ([MissionPuzzle.checkAnswer]), never an AI
/// grader.
class MissionPuzzleScreen extends ConsumerStatefulWidget {
  const MissionPuzzleScreen({super.key});

  @override
  ConsumerState<MissionPuzzleScreen> createState() => _MissionPuzzleScreenState();
}

class _MissionPuzzleScreenState extends ConsumerState<MissionPuzzleScreen> {
  final _answer = TextEditingController();
  bool _wrongAttempt = false;
  int _hintsUsed = 0;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _submit() {
    final controller = ref.read(activeMissionControllerProvider.notifier);
    final correct = controller.solvePuzzle(_answer.text, hintsUsed: _hintsUsed);
    if (correct) {
      context.pushReplacement(AppRoute.missionComplete.path);
    } else {
      setState(() => _wrongAttempt = true);
    }
  }

  void _revealAnswer() {
    final controller = ref.read(activeMissionControllerProvider.notifier);
    controller.solvePuzzle('', revealed: true);
    context.pushReplacement(AppRoute.missionComplete.path);
  }

  @override
  Widget build(BuildContext context) {
    final puzzle = ref.watch(activeMissionControllerProvider).pendingPuzzle;
    if (puzzle == null) {
      // Nothing pending (e.g. a cold navigation to this route) — nothing
      // useful to show.
      return Scaffold(
        backgroundColor: RD.bg,
        body: Center(
          child: Text('No puzzle is waiting right now.', style: RD.body),
        ),
      );
    }

    return Scaffold(
      backgroundColor: RD.bg,
      appBar: AppBar(
        backgroundColor: RD.bg,
        foregroundColor: RD.textPrimary,
        title: const Text('One Last Thing…'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RD.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.psychology_alt_rounded, color: RD.amber, size: 56),
            const SizedBox(height: RD.md),
            Text(_typeLabel(puzzle.type), style: RD.sectionLabel.copyWith(color: RD.amber)),
            const SizedBox(height: RD.sm),
            Text(puzzle.prompt, style: RD.title.copyWith(fontSize: 20)),
            const SizedBox(height: RD.xl),
            TextField(
              controller: _answer,
              autofocus: true,
              style: const TextStyle(color: RD.textPrimary),
              decoration: InputDecoration(
                hintText: 'Your answer',
                hintStyle: const TextStyle(color: RD.textFaint),
                filled: true,
                fillColor: RD.panel,
                border: OutlineInputBorder(borderRadius: RD.brMd, borderSide: BorderSide.none),
                errorText: _wrongAttempt ? "That's not quite it — try again." : null,
              ),
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_wrongAttempt) setState(() => _wrongAttempt = false);
              },
            ),
            const SizedBox(height: RD.md),
            if (puzzle.hintLevels.isNotEmpty)
              AskTheGuidePanel(
                subjectId: 'hint:${puzzle.id}',
                hintLevels: puzzle.hintLevels,
                answerRevealText: puzzle.answerRevealText,
                hintsUsed: _hintsUsed,
                onRequestHint: () => setState(() => _hintsUsed++),
                onRevealAnswer: (puzzle.answerRevealText ?? '').trim().isEmpty
                    ? null
                    : _revealAnswer,
              ),
            const Spacer(),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: RD.green, foregroundColor: RD.onGreen),
                onPressed: _submit,
                child: const Text('Submit', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _typeLabel(String type) => switch (type) {
        'memory' => 'MEMORY',
        'observation' => 'OBSERVATION',
        'deduction' => 'DEDUCTION',
        'history' => 'HISTORY',
        'code' => 'CODE',
        'connection' => 'CONNECTION',
        'direction' => 'DIRECTION',
        _ => type.toUpperCase(),
      };
}
