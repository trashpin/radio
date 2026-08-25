/// One fragment of an adventure's Treasure Map (`mission_map_pieces`,
/// migration 0076). The fragment art in [imageUrl] is authored content —
/// whether a given player has actually found this piece is never stored
/// here; see `treasureMapProvider`, which derives that from
/// `MissionProgress.firedContentIds`/`unlockedOldWorldIds` against
/// whichever clue's `unlocksMapPieceId` points at this row.
class MissionMapPiece {
  const MissionMapPiece({
    required this.id,
    required this.missionId,
    this.pieceOrder = 0,
    required this.title,
    this.imageUrl,
  });

  final String id;
  final String missionId;
  final int pieceOrder;

  /// Admin-facing label only, never shown to players.
  final String title;
  final String? imageUrl;

  factory MissionMapPiece.fromJson(Map<String, dynamic> j) => MissionMapPiece(
        id: (j['id'] ?? '').toString(),
        missionId: (j['mission_id'] ?? '').toString(),
        pieceOrder: (j['piece_order'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '') as String,
        imageUrl: j['image_url'] as String?,
      );

  Map<String, dynamic> toWrite() => {
        'mission_id': missionId,
        'piece_order': pieceOrder,
        'title': title,
        'image_url': imageUrl,
      };
}

// Shared clue-type vocabulary — used by mission_story_steps (authoring),
// mission_travel_stories, and old_worlds (the two runtime targets).
const kClueTypeImage = 'image';
const kClueTypeAudio = 'audio';
const kClueTypeText = 'text';
const kClueTypeVideo = 'video';
const kClueTypeRiddle = 'riddle';
const kClueTypeMapFragment = 'map_fragment';
const kClueTypeCharacterMessage = 'character_message';

const List<String> kClueTypes = [
  kClueTypeImage,
  kClueTypeAudio,
  kClueTypeText,
  kClueTypeVideo,
  kClueTypeRiddle,
  kClueTypeMapFragment,
  kClueTypeCharacterMessage,
];
