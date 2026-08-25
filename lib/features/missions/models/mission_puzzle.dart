/// A test of attention/reasoning (`mission_puzzles`, migration 0063).
/// [stopId] null means a mission-level puzzle — today, always the final
/// puzzle before Mission Complete; the schema doesn't assume that forever.
///
/// [type] intentionally stays free text (not a fixed enum) — the spec names
/// seven kinds (memory/observation/deduction/history/code/connection/
/// direction) but only a subset need real runtime support today; the data
/// model is ready for the rest without a migration.
class MissionPuzzle {
  const MissionPuzzle({
    required this.id,
    required this.missionId,
    this.stopId,
    this.type = 'memory',
    required this.prompt,
    this.acceptedAnswers = const [],
    this.hint,
    this.hint2,
    this.hint3,
    this.answerRevealText,
    this.hintXpPenalty = 5,
    this.successText,
    this.relatedFactKeys = const [],
    this.rewardXp = 0,
    this.sequence = 0,
  });

  final String id;
  final String missionId;
  final String? stopId;
  final String type;
  final String prompt;
  final List<String> acceptedAnswers;

  /// Hint level 1 (NUDGE).
  final String? hint;

  /// Hint level 2 (CLUE).
  final String? hint2;

  /// Hint level 3 (GUIDE ME).
  final String? hint3;

  /// Last-resort teaching moment — the answer PLUS why, offered by
  /// [AskTheGuidePanel] only after every available hint level above has
  /// already been shown. Never a bare "Answer: X" (an admin-content
  /// responsibility, not enforced by code).
  final String? answerRevealText;

  /// XP deducted from [rewardXp] per hint level actually used — see
  /// [ActiveMissionController.solvePuzzle]/`awardBonusXp` call sites for
  /// where this is applied. Revealing the answer awards 0 XP outright.
  final int hintXpPenalty;
  final String? successText;
  final List<String> relatedFactKeys;
  final int rewardXp;
  final int sequence;

  /// Every non-empty hint level, in order — the one list
  /// [AskTheGuidePanel] iterates, regardless of how many levels an admin
  /// actually filled in.
  List<String> get hintLevels => [
        if ((hint ?? '').trim().isNotEmpty) hint!,
        if ((hint2 ?? '').trim().isNotEmpty) hint2!,
        if ((hint3 ?? '').trim().isNotEmpty) hint3!,
      ];

  /// Case-insensitive, whitespace-trimmed match against any accepted
  /// answer — a simple, honest check, not an AI grader (spec: "Do not
  /// implement an advanced AI puzzle-generation system yet").
  bool checkAnswer(String given) {
    final normalized = given.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return acceptedAnswers.any((a) => a.trim().toLowerCase() == normalized);
  }

  static List<String> _strs(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  factory MissionPuzzle.fromJson(Map<String, dynamic> j) => MissionPuzzle(
        id: (j['id'] ?? '').toString(),
        missionId: (j['mission_id'] ?? '').toString(),
        stopId: j['stop_id']?.toString(),
        type: (j['type'] ?? 'memory') as String,
        prompt: (j['prompt'] ?? '') as String,
        acceptedAnswers: _strs(j['accepted_answers']),
        hint: j['hint'] as String?,
        hint2: j['hint2'] as String?,
        hint3: j['hint3'] as String?,
        answerRevealText: j['answer_reveal_text'] as String?,
        hintXpPenalty: (j['hint_xp_penalty'] as num?)?.toInt() ?? 5,
        successText: j['success_text'] as String?,
        relatedFactKeys: _strs(j['related_fact_keys']),
        rewardXp: (j['reward_xp'] as num?)?.toInt() ?? 0,
        sequence: (j['sequence'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toWrite() => {
        'mission_id': missionId,
        'stop_id': stopId,
        'type': type,
        'prompt': prompt,
        'accepted_answers': acceptedAnswers,
        'hint': hint,
        'hint2': hint2,
        'hint3': hint3,
        'answer_reveal_text': answerRevealText,
        'hint_xp_penalty': hintXpPenalty,
        'success_text': successText,
        'related_fact_keys': relatedFactKeys,
        'reward_xp': rewardXp,
        'sequence': sequence,
      };
}
