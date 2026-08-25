import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/data/treasure_map_provider.dart';
import 'package:explorer_os_mobile/features/missions/models/guide_step.dart';

/// Picks "what should the Guide say right now" — pure, on-demand
/// aggregation, exactly like `treasureMapProvider`. Deliberately a PULL
/// model, not a live push/interrupt engine: this recomputes fresh every
/// time the Guide tab is opened/rebuilt, using [ActiveMissionState] that
/// `ActiveMissionController`/`MissionStoryEngine` already maintain — it
/// never touches that pipeline. "Already shown" reuses `state.firedIds`,
/// the same set travel stories use (see
/// `ActiveMissionController.markGuideStepShown`).
final nextGuideStepProvider = FutureProvider.family<GuideStep?, String>((ref, missionId) async {
  final state = ref.watch(activeMissionControllerProvider);
  final steps = await ref.watch(guideStepsForMissionProvider(missionId).future);
  final treasureMap = await ref.watch(treasureMapProvider(missionId).future);
  final anyPieceFound = treasureMap.foundCount > 0;

  for (final step in steps) {
    if (state.firedIds.contains(step.id)) continue;
    if (_triggerSatisfied(step, state, anyPieceFound)) return step;
  }
  return null;
});

bool _triggerSatisfied(GuideStep step, ActiveMissionState state, bool anyPieceFound) {
  switch (step.triggerType) {
    case kGuideTriggerMissionStart:
      return state.hasActiveMission;
    case kGuideTriggerDistanceFromDestination:
      return state.lastDistanceMeters != null &&
          step.triggerDistanceMeters != null &&
          state.lastDistanceMeters! <= step.triggerDistanceMeters!;
    case kGuideTriggerArrival:
      return state.awaitingQr && (step.stopId == null || state.currentStop?.id == step.stopId);
    case kGuideTriggerQrScan:
    case kGuideTriggerPreviousStepComplete:
      if (step.requiredPreviousGuideStepId != null) {
        return state.firedIds.contains(step.requiredPreviousGuideStepId);
      }
      return step.stopId != null && state.completedStopIds.contains(step.stopId);
    case kGuideTriggerMapPieceCollected:
      return anyPieceFound;
    case kGuideTriggerPuzzleSolved:
      return step.puzzleId != null && state.solvedPuzzleIds.contains(step.puzzleId);
    case kGuideTriggerManualDiscovery:
    default:
      return true;
  }
}
