import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_puzzle.dart';

const List<String> _kPuzzleTypes = [
  'memory',
  'observation',
  'deduction',
  'history',
  'code',
  'connection',
  'direction',
];

/// Admin -> a mission's facts (information the story reveals that may
/// matter later) and its final puzzle (a test of attention/reasoning drawn
/// from those facts). This is deliberately NOT an AI puzzle-generation
/// system — facts and answers are all admin-authored; the runtime only ever
/// does a case-insensitive string match (see `MissionPuzzle.checkAnswer`).
class MissionFactsPuzzlesPage extends ConsumerWidget {
  const MissionFactsPuzzlesPage({super.key, required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final factsAsync = ref.watch(factsForMissionProvider(mission.id));
    final puzzlesAsync = ref.watch(puzzlesForMissionProvider(mission.id));

    return Scaffold(
      appBar: AppBar(title: Text('${mission.title} — Facts & Puzzle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(
              child: Text('Facts', style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: () => _addFact(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ]),
          const Text(
            'Information a story reveals that the player may need to recall later — '
            'tag it on a travel story or Old World as "reveals this fact."',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          factsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AdminEmptyState(message: 'Could not load facts: $e'),
            data: (facts) => facts.isEmpty
                ? const AdminEmptyState(message: 'No facts yet.')
                : Column(children: [
                    for (final f in facts)
                      AdminSectionCard(
                        child: ListTile(
                          title: Text(f.label),
                          subtitle: Text('${f.key} → ${f.value}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              await ref.read(missionRepositoryProvider).deleteFact(f.id);
                              ref.read(missionsRefreshProvider.notifier).bump();
                            },
                          ),
                        ),
                      ),
                  ]),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: Text('Final Puzzle', style: Theme.of(context).textTheme.titleMedium),
            ),
          ]),
          const Text(
            'Shown after the last stop, before Mission Complete, and always blocks '
            'progression until solved. For a non-blocking "test of wits" tied to one '
            'stop\'s QR discovery chapter, use that stop\'s own detail page instead.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          puzzlesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => AdminEmptyState(message: 'Could not load puzzles: $e'),
            data: (puzzles) {
              final finalPuzzles = puzzles.where((p) => p.stopId == null).toList();
              return Column(children: [
                for (final p in finalPuzzles)
                  AdminSectionCard(
                    child: ListTile(
                      leading: StatusBadge(BadgeStatus.review, label: p.type),
                      title: Text(p.prompt),
                      subtitle: Text('Accepts: ${p.acceptedAnswers.join(", ")}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Preview hints',
                          icon: const Icon(Icons.visibility_outlined),
                          onPressed: () => showPuzzleHintsPreviewDialog(context, p),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => showPuzzleEditorDialog(context, ref,
                              missionId: mission.id, stopId: null, puzzle: p),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            await ref.read(missionRepositoryProvider).deletePuzzle(p.id);
                            ref.read(missionsRefreshProvider.notifier).bump();
                          },
                        ),
                      ]),
                    ),
                  ),
                if (finalPuzzles.isEmpty)
                  OutlinedButton.icon(
                    onPressed: () =>
                        showPuzzleEditorDialog(context, ref, missionId: mission.id, stopId: null),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add final puzzle'),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addFact(BuildContext context, WidgetRef ref) async {
    final key = TextEditingController();
    final label = TextEditingController();
    final value = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add fact'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: key,
                decoration: const InputDecoration(
                    labelText: 'Key (e.g. thomas_object)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: label,
                decoration: const InputDecoration(
                    labelText: 'Label (e.g. "What object did Thomas carry?")',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: value,
                decoration: const InputDecoration(
                    labelText: 'Value (e.g. "Silver pocket watch")',
                    border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Add')),
        ],
      ),
    );

    if (saved != true || key.text.trim().isEmpty || value.text.trim().isEmpty) return;
    await ref.read(missionRepositoryProvider).createFact({
      'mission_id': mission.id,
      'key': key.text.trim(),
      'label': label.text.trim().isEmpty ? key.text.trim() : label.text.trim(),
      'value': value.text.trim(),
    });
    ref.read(missionsRefreshProvider.notifier).bump();
  }

}

/// Shared create/edit dialog for a [MissionPuzzle] — the SAME mechanism
/// whether it's the mission-level final puzzle ([stopId] null, gates
/// Mission Complete) or a stop-level "test of wits" ([stopId] set, shown
/// right after that stop's QR discovery chapter and never blocks
/// progression — see `ActiveMissionController.awardBonusXp`). Both cases
/// share this one dialog rather than duplicating the puzzle form.
Future<void> showPuzzleEditorDialog(
  BuildContext context,
  WidgetRef ref, {
  required String missionId,
  required String? stopId,
  MissionPuzzle? puzzle,
}) async {
  final prompt = TextEditingController(text: puzzle?.prompt ?? '');
  final answers = TextEditingController(text: puzzle?.acceptedAnswers.join(', ') ?? '');
  final hint = TextEditingController(text: puzzle?.hint ?? '');
  final hint2 = TextEditingController(text: puzzle?.hint2 ?? '');
  final hint3 = TextEditingController(text: puzzle?.hint3 ?? '');
  final answerReveal = TextEditingController(text: puzzle?.answerRevealText ?? '');
  final hintXpPenalty = TextEditingController(text: '${puzzle?.hintXpPenalty ?? 5}');
  final successText = TextEditingController(text: puzzle?.successText ?? '');
  final rewardXp = TextEditingController(text: '${puzzle?.rewardXp ?? 0}');
  var type = puzzle?.type ?? 'memory';

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(puzzle == null
            ? (stopId == null ? 'Add final puzzle' : 'Add test of wits')
            : (stopId == null ? 'Edit final puzzle' : 'Edit test of wits')),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration:
                      const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                  items: [
                    for (final t in _kPuzzleTypes) DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setState(() => type = v ?? type),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: prompt,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Question (e.g. "What object did Thomas carry?")',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: answers,
                  decoration: const InputDecoration(
                      labelText: 'Accepted answers, comma-separated',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                const Text('Ask the Guide — progressive hints', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                    controller: hint,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Hint 1 — Nudge (subtle, never the answer)',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: hint2,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Hint 2 — Clue (stronger, points at the solution)',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: hint3,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Hint 3 — Guide Me (explains how, not the final answer)',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: answerReveal,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Reveal Answer text',
                        helperText: 'A teaching moment — explain the answer AND why, never just '
                            '"Answer: X." Only offered after every hint above has been shown.',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                  controller: hintXpPenalty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'XP penalty per hint level used',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                TextField(
                    controller: successText,
                    decoration: const InputDecoration(
                        labelText: 'Success message (optional)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                  controller: rewardXp,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Reward XP (full amount, before any hint penalty)',
                      border: OutlineInputBorder()),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(puzzle == null ? 'Add' : 'Save')),
          ],
        ),
      ),
    );

    if (saved != true || prompt.text.trim().isEmpty) return;
    final row = {
      'type': type,
      'prompt': prompt.text.trim(),
      'accepted_answers':
          answers.text.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty).toList(),
      'hint': hint.text.trim().isEmpty ? null : hint.text.trim(),
      'hint2': hint2.text.trim().isEmpty ? null : hint2.text.trim(),
      'hint3': hint3.text.trim().isEmpty ? null : hint3.text.trim(),
      'answer_reveal_text': answerReveal.text.trim().isEmpty ? null : answerReveal.text.trim(),
      'hint_xp_penalty': int.tryParse(hintXpPenalty.text.trim()) ?? 5,
      'success_text': successText.text.trim().isEmpty ? null : successText.text.trim(),
      'reward_xp': int.tryParse(rewardXp.text.trim()) ?? 0,
    };
  final repo = ref.read(missionRepositoryProvider);
  if (puzzle == null) {
    await repo.createPuzzle({...row, 'mission_id': missionId, 'stop_id': stopId});
  } else {
    await repo.updatePuzzle(puzzle.id, row);
  }
  ref.read(missionsRefreshProvider.notifier).bump();
}

/// Read-only walkthrough of every hint level exactly as
/// [AskTheGuidePanel]/`TreasureMapScreen` would show them to a player, in
/// order — spec: "The administrator should be able to preview all hint
/// levels."
Future<void> showPuzzleHintsPreviewDialog(BuildContext context, MissionPuzzle puzzle) async {
  final levels = puzzle.hintLevels;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Hint preview'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(puzzle.prompt, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            if (levels.isEmpty) const Text('No hints configured yet.', style: TextStyle(color: Colors.grey)),
            for (var i = 0; i < levels.length; i++) ...[
              Text(['Hint 1 — Nudge', 'Hint 2 — Clue', 'Hint 3 — Guide Me'][i],
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(levels[i]),
              const SizedBox(height: 12),
            ],
            if ((puzzle.answerRevealText ?? '').trim().isNotEmpty) ...[
              const Text('Reveal Answer',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(puzzle.answerRevealText!),
              const SizedBox(height: 12),
            ],
            Text('XP penalty per hint level: ${puzzle.hintXpPenalty} '
                '(reward: ${puzzle.rewardXp} XP full, 0 XP if revealed)',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
      ],
    ),
  );
}
