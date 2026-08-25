import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/missions/data/mission_progress_repository.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/guide_step.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_map_piece.dart';

/// One "Clues Found" list item — a clue-flagged `mission_travel_stories`
/// or `old_worlds` row the player has actually reached, normalized into
/// one shape so the Treasure Map panel doesn't need to know which table a
/// clue came from. Never constructed for a clue the player hasn't found —
/// see [TreasureMapData], which only ever includes rows already present in
/// the player's own `mission_progress` arrays.
class FoundClue {
  const FoundClue({
    required this.id,
    required this.title,
    required this.clueType,
    this.text,
    this.audioUrl,
    this.imageUrl,
    this.videoUrl,
    this.characterName,
    this.characterImageUrl,
  });

  final String id;
  final String title;
  final String clueType;

  /// The clue's readable content — a riddle/text clue's body, OR the
  /// accessible transcript of an audio/character-message clue (spec:
  /// "The audio should also have a readable text transcript").
  final String? text;
  final String? audioUrl;
  final String? imageUrl;
  final String? videoUrl;
  final String? characterName;
  final String? characterImageUrl;
}

class MapPieceStatus {
  const MapPieceStatus({required this.piece, required this.found});
  final MissionMapPiece piece;
  final bool found;

  /// Locked pieces never carry their real art to the UI (spec: "Do NOT
  /// reveal locked pieces") — callers should use this instead of
  /// `piece.imageUrl` directly.
  String? get imageUrlIfFound => found ? piece.imageUrl : null;
}

class TreasureMapData {
  const TreasureMapData({required this.pieces, required this.clues});
  final List<MapPieceStatus> pieces;
  final List<FoundClue> clues;

  int get foundCount => pieces.where((p) => p.found).length;
  int get totalCount => pieces.length;
}

/// Derives "what has this player discovered so far in this mission" —
/// deliberately NOT a new trigger/progress system. Found state comes
/// entirely from the existing `mission_progress.fired_content_ids`
/// (travel stories) and `unlocked_old_world_ids` (Old Worlds), which
/// `ActiveMissionController` already writes the instant a beat plays or a
/// QR resolves. This provider only reads and cross-references; it never
/// touches `ActiveMissionController`/`MissionStoryEngine`.
final treasureMapProvider = FutureProvider.family<TreasureMapData, String>((ref, missionId) async {
  final repo = ref.watch(missionRepositoryProvider);
  final progressRepo = ref.watch(missionProgressRepositoryProvider);

  final progress = await progressRepo.forMission(missionId);
  final firedIds = (progress?.firedContentIds ?? const <String>[]).toSet();
  final unlockedOldWorldIds = (progress?.unlockedOldWorldIds ?? const <String>[]).toSet();

  final pieces = await repo.mapPiecesForMission(missionId);
  final travelStories = await repo.travelStoriesForMission(missionId);
  final stops = await repo.stopsForMission(missionId);
  final oldWorldIds = stops.map((s) => s.oldWorldId).whereType<String>().toList();
  final oldWorlds = await repo.oldWorldsByIds(oldWorldIds);
  final guideSteps = await repo.guideStepsForMission(missionId);

  final foundPieceIds = <String>{};
  final clues = <FoundClue>[];

  for (final story in travelStories) {
    if (!story.isClue || !firedIds.contains(story.id)) continue;
    if (story.unlocksMapPieceId != null) foundPieceIds.add(story.unlocksMapPieceId!);
    String? characterName;
    String? characterImageUrl;
    if (story.characterId != null) {
      final character = await repo.characterById(story.characterId!);
      characterName = character?.name;
      characterImageUrl = character?.imageUrl;
    }
    clues.add(FoundClue(
      id: story.id,
      title: story.text.length > 48 ? '${story.text.substring(0, 48)}…' : story.text,
      clueType: story.clueType ?? kClueTypeText,
      text: story.text,
      audioUrl: story.audioUrl,
      imageUrl: story.clueImageUrl,
      characterName: characterName ?? story.speakerName,
      characterImageUrl: characterImageUrl,
    ));
  }

  for (final world in oldWorlds) {
    if (!world.isClue || !unlockedOldWorldIds.contains(world.id)) continue;
    if (world.unlocksMapPieceId != null) foundPieceIds.add(world.unlocksMapPieceId!);
    String? characterName;
    String? characterImageUrl;
    if (world.characterId != null) {
      final character = await repo.characterById(world.characterId!);
      characterName = character?.name;
      characterImageUrl = character?.imageUrl;
    }
    clues.add(FoundClue(
      id: world.id,
      title: world.title,
      clueType: world.clueType ?? kClueTypeCharacterMessage,
      text: world.clueText ?? world.narrationText,
      audioUrl: world.narrationAudioUrl,
      imageUrl: world.clueImageUrl,
      videoUrl: world.characterVideoUrl,
      characterName: characterName ?? world.narratorName,
      characterImageUrl: characterImageUrl,
    ));
  }

  // Guide Steps (talked through the Guide tab, see nextGuideStepProvider)
  // are one more clue source — a CLUE-content step or any step with
  // unlocksMapPieceId set feeds the same Treasure Map, using the exact
  // same `firedIds` set every other clue source already uses (see
  // ActiveMissionController.markGuideStepShown).
  for (final step in guideSteps) {
    final isClueLike = step.contentType == kGuideContentClue || step.unlocksMapPieceId != null;
    if (!isClueLike || !firedIds.contains(step.id)) continue;
    if (step.unlocksMapPieceId != null) foundPieceIds.add(step.unlocksMapPieceId!);
    String? characterName;
    String? characterImageUrl;
    if (step.characterId != null) {
      final character = await repo.characterById(step.characterId!);
      characterName = character?.name;
      characterImageUrl = character?.imageUrl;
    }
    final text = (step.script ?? '').trim();
    clues.add(FoundClue(
      id: step.id,
      title: text.length > 48 ? '${text.substring(0, 48)}…' : (text.isEmpty ? step.title : text),
      clueType: _clueTypeForGuideContent(step.contentType),
      text: text.isEmpty ? null : text,
      audioUrl: step.audioUrl,
      imageUrl: step.imageUrl,
      videoUrl: step.avatarVideoUrl,
      characterName: characterName,
      characterImageUrl: characterImageUrl,
    ));
  }

  final pieceStatuses = [
    for (final piece in pieces) MapPieceStatus(piece: piece, found: foundPieceIds.contains(piece.id)),
  ];

  return TreasureMapData(pieces: pieceStatuses, clues: clues);
});

/// Maps a Guide Step's [GuideStep.contentType] onto the Treasure Map's own
/// clue-type vocabulary — the two are separate concepts (a Guide Step's
/// content type also covers PONDER/CHOICE/etc., which never appear in the
/// Clues Found list at all; only genuinely clue-like content types reach
/// this function, see the `isClueLike` check above).
String _clueTypeForGuideContent(String guideContentType) => switch (guideContentType) {
      kGuideContentImage || kGuideContentInspect => kClueTypeImage,
      kGuideContentAudio => kClueTypeAudio,
      kGuideContentVideo => kClueTypeVideo,
      kGuideContentMap || kGuideContentDiscovery => kClueTypeMapFragment,
      kGuideContentTalk => kClueTypeCharacterMessage,
      _ => kClueTypeText,
    };
