/// One player's progress through one [Mission] (`mission_progress`,
/// migration 0061) — self-only RLS, one row per (user, mission).
class MissionProgress {
  const MissionProgress({
    required this.id,
    required this.userId,
    required this.missionId,
    this.currentStopId,
    this.completedStopIds = const [],
    this.discoveredLocationIds = const [],
    this.unlockedOldWorldIds = const [],
    this.firedContentIds = const [],
    this.revealedFactKeys = const [],
    this.solvedPuzzleIds = const [],
    this.xp = 0,
    this.status = 'not_started',
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final String userId;
  final String missionId;
  final String? currentStopId;
  final List<String> completedStopIds;
  final List<String> discoveredLocationIds;
  final List<String> unlockedOldWorldIds;

  /// Which `mission_travel_stories` rows have already fired for this player
  /// — the persistence-layer half of "prevent stories from playing
  /// repeatedly" (the in-memory engine is the other half, for same-session
  /// speed).
  final List<String> firedContentIds;

  /// Which [MissionFact.key]s the player has actually heard so far —
  /// populated from [MissionTravelStory.revealsFactKeys]/
  /// [OldWorld.revealsFactKeys] as content plays.
  final List<String> revealedFactKeys;

  /// Which `mission_puzzles` the player has already solved.
  final List<String> solvedPuzzleIds;
  final int xp;

  /// 'not_started' | 'in_progress' | 'completed' | 'abandoned'.
  final String status;
  final DateTime? startedAt;
  final DateTime? completedAt;

  bool get isCompleted => status == 'completed';
  bool get isInProgress => status == 'in_progress';

  static List<String> _strs(dynamic v) =>
      v is List ? v.map((e) => e.toString()).toList() : const [];

  factory MissionProgress.fromJson(Map<String, dynamic> j) => MissionProgress(
        id: (j['id'] ?? '').toString(),
        userId: (j['user_id'] ?? '').toString(),
        missionId: (j['mission_id'] ?? '').toString(),
        currentStopId: j['current_stop_id']?.toString(),
        completedStopIds: _strs(j['completed_stop_ids']),
        discoveredLocationIds: _strs(j['discovered_location_ids']),
        unlockedOldWorldIds: _strs(j['unlocked_old_world_ids']),
        firedContentIds: _strs(j['fired_content_ids']),
        revealedFactKeys: _strs(j['revealed_fact_keys']),
        solvedPuzzleIds: _strs(j['solved_puzzle_ids']),
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        status: (j['status'] ?? 'not_started') as String,
        startedAt: DateTime.tryParse('${j['started_at']}'),
        completedAt: DateTime.tryParse('${j['completed_at']}'),
      );

  Map<String, dynamic> toWrite() => {
        'user_id': userId,
        'mission_id': missionId,
        'current_stop_id': currentStopId,
        'completed_stop_ids': completedStopIds,
        'discovered_location_ids': discoveredLocationIds,
        'unlocked_old_world_ids': unlockedOldWorldIds,
        'fired_content_ids': firedContentIds,
        'revealed_fact_keys': revealedFactKeys,
        'solved_puzzle_ids': solvedPuzzleIds,
        'xp': xp,
        'status': status,
        'started_at': startedAt?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
      };

  MissionProgress copyWith({
    String? currentStopId,
    List<String>? completedStopIds,
    List<String>? discoveredLocationIds,
    List<String>? unlockedOldWorldIds,
    List<String>? firedContentIds,
    List<String>? revealedFactKeys,
    List<String>? solvedPuzzleIds,
    int? xp,
    String? status,
    DateTime? startedAt,
    DateTime? completedAt,
  }) =>
      MissionProgress(
        id: id,
        userId: userId,
        missionId: missionId,
        currentStopId: currentStopId ?? this.currentStopId,
        completedStopIds: completedStopIds ?? this.completedStopIds,
        discoveredLocationIds: discoveredLocationIds ?? this.discoveredLocationIds,
        unlockedOldWorldIds: unlockedOldWorldIds ?? this.unlockedOldWorldIds,
        firedContentIds: firedContentIds ?? this.firedContentIds,
        revealedFactKeys: revealedFactKeys ?? this.revealedFactKeys,
        solvedPuzzleIds: solvedPuzzleIds ?? this.solvedPuzzleIds,
        xp: xp ?? this.xp,
        status: status ?? this.status,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
      );
}
