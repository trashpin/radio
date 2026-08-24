/// A named piece of information a story revealed (`mission_facts`,
/// migration 0063). The player may not know why it matters when they first
/// hear it — a later [MissionPuzzle] may reference [key] via
/// `relatedFactKeys`. [label]/[value] are kept verbatim (what the story
/// actually said), never re-derived or inferred.
class MissionFact {
  const MissionFact({
    required this.id,
    required this.missionId,
    required this.key,
    required this.label,
    required this.value,
  });

  final String id;
  final String missionId;

  /// The stable id a puzzle references — e.g. `'thomas_object'`.
  final String key;

  /// A human-readable description of the fact, for the admin list — e.g.
  /// "What object did Thomas carry?"
  final String label;

  /// The actual answer/content — e.g. "Silver pocket watch".
  final String value;

  factory MissionFact.fromJson(Map<String, dynamic> j) => MissionFact(
        id: (j['id'] ?? '').toString(),
        missionId: (j['mission_id'] ?? '').toString(),
        key: (j['key'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        value: (j['value'] ?? '') as String,
      );

  Map<String, dynamic> toWrite() => {
        'mission_id': missionId,
        'key': key,
        'label': label,
        'value': value,
      };
}
