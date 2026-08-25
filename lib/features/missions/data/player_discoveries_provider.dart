import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/missions/data/mission_progress_repository.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_fact.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_progress.dart';
import 'package:explorer_os_mobile/features/missions/models/old_world.dart';

/// One mission paired with the signed-in player's progress through it — the
/// "My Discoveries" list item, reusing [Mission]/[MissionProgress] as-is.
class MissionDiscoverySummary {
  const MissionDiscoverySummary({required this.mission, required this.progress});
  final Mission mission;
  final MissionProgress progress;
}

/// Everything "My Discoveries" shows — built entirely from data the game
/// already durably tracks in `mission_progress` (see
/// [MissionProgressRepository]): nothing here is a new reward/collection
/// system, just an aggregation across every mission the player has played.
class PlayerDiscoveries {
  const PlayerDiscoveries({
    required this.completed,
    required this.inProgress,
    required this.unlockedOldWorlds,
    required this.learnedFacts,
    required this.totalXp,
  });

  final List<MissionDiscoverySummary> completed;
  final List<MissionDiscoverySummary> inProgress;

  /// Every `old_worlds` chapter/character the player has unlocked via a QR
  /// scan, across every mission — [ActiveMissionController.unlockedOldWorldIds]
  /// is what feeds this over time.
  final List<OldWorld> unlockedOldWorlds;

  /// Every [MissionFact] the player has actually heard revealed, across
  /// every mission, deduplicated by fact id.
  final List<MissionFact> learnedFacts;
  final int totalXp;

  bool get isEmpty =>
      completed.isEmpty && inProgress.isEmpty && unlockedOldWorlds.isEmpty && learnedFacts.isEmpty;
}

final playerDiscoveriesProvider = FutureProvider<PlayerDiscoveries>((ref) async {
  final progressList = await ref.watch(allMissionProgressProvider.future);
  final repo = ref.watch(missionRepositoryProvider);

  if (progressList.isEmpty) {
    return const PlayerDiscoveries(
      completed: [],
      inProgress: [],
      unlockedOldWorlds: [],
      learnedFacts: [],
      totalXp: 0,
    );
  }

  final missionIds = {for (final p in progressList) p.missionId};
  final missions = await Future.wait(missionIds.map(repo.byId));
  final missionsById = {for (final m in missions.whereType<Mission>()) m.id: m};

  final oldWorldIds = {for (final p in progressList) ...p.unlockedOldWorldIds};
  final oldWorldsFuture = repo.oldWorldsByIds(oldWorldIds.toList());

  final factsByMissionFuture = {
    for (final id in missionIds) id: repo.factsForMission(id),
  };
  final factsByMission = {
    for (final entry in factsByMissionFuture.entries) entry.key: await entry.value,
  };

  final completed = <MissionDiscoverySummary>[];
  final inProgress = <MissionDiscoverySummary>[];
  final learnedFacts = <MissionFact>[];
  final seenFactIds = <String>{};

  for (final progress in progressList) {
    final mission = missionsById[progress.missionId];
    if (mission == null) continue;
    final summary = MissionDiscoverySummary(mission: mission, progress: progress);
    if (progress.isCompleted) {
      completed.add(summary);
    } else if (progress.isInProgress) {
      inProgress.add(summary);
    }

    for (final fact in factsByMission[progress.missionId] ?? const <MissionFact>[]) {
      if (progress.revealedFactKeys.contains(fact.key) && seenFactIds.add(fact.id)) {
        learnedFacts.add(fact);
      }
    }
  }

  completed.sort((a, b) {
    final aDate = a.progress.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.progress.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  });

  final totalXp = progressList.fold<int>(0, (sum, p) => sum + p.xp);

  return PlayerDiscoveries(
    completed: completed,
    inProgress: inProgress,
    unlockedOldWorlds: await oldWorldsFuture,
    learnedFacts: learnedFacts,
    totalXp: totalXp,
  );
});
