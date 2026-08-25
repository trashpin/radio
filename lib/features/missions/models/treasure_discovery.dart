/// The Treasure Hunt Discovery stage for one mission stop
/// (`treasure_discoveries`, migration 0072) — a second layer of
/// exploration AFTER GPS arrival, before the player reaches the existing
/// QR scanner. GPS already got them to [MissionStop.arrivalRadiusMeters];
/// this is what happens next: a stylized map + written clue + a
/// progressive hint ladder that encourages physically looking around
/// instead of walking to a pin. The QR itself is never duplicated here —
/// see [MissionStop.qrPortalId], which this stage still resolves through.
class TreasureDiscovery {
  const TreasureDiscovery({
    required this.id,
    required this.missionId,
    required this.stopId,
    this.treasureMapImageUrl,
    this.clueText,
    this.hint1Text,
    this.hint2Text,
    this.finalHintText,
    this.discoveryTitle,
    this.landmarksText,
    this.difficulty,
    this.searchAreaMeters,
  });

  final String id;
  final String missionId;
  final String stopId;

  /// Mystery/adventure artwork of the real search area — NOT a GPS map,
  /// never a pin on the exact QR spot. Null shows a styled placeholder.
  final String? treasureMapImageUrl;
  final String? clueText;

  /// Progressive hint ladder — each is optional; the UI only offers hints
  /// that are actually set.
  final String? hint1Text;
  final String? hint2Text;
  final String? finalHintText;

  /// Shown on "YOU FOUND IT" instead of a generic label, e.g. "YOU FOUND
  /// THE FIRST PIECE".
  final String? discoveryTitle;

  /// Admin-facing production notes — real landmarks a clue references.
  final String? landmarksText;

  /// Free text, not a fixed enum — suggested vocabulary: easy, medium, hard.
  final String? difficulty;

  /// Optional, soft-bounded search guidance shown to the player — never
  /// the exact QR distance/bearing.
  final double? searchAreaMeters;

  bool get hasMapImage => (treasureMapImageUrl ?? '').trim().isNotEmpty;
  bool get hasHint1 => (hint1Text ?? '').trim().isNotEmpty;
  bool get hasHint2 => (hint2Text ?? '').trim().isNotEmpty;
  bool get hasFinalHint => (finalHintText ?? '').trim().isNotEmpty;

  static double? _dOrNull(dynamic v) => (v as num?)?.toDouble();

  factory TreasureDiscovery.fromJson(Map<String, dynamic> j) => TreasureDiscovery(
        id: (j['id'] ?? '').toString(),
        missionId: (j['mission_id'] ?? '').toString(),
        stopId: (j['stop_id'] ?? '').toString(),
        treasureMapImageUrl: j['treasure_map_image_url'] as String?,
        clueText: j['clue_text'] as String?,
        hint1Text: j['hint_1_text'] as String?,
        hint2Text: j['hint_2_text'] as String?,
        finalHintText: j['final_hint_text'] as String?,
        discoveryTitle: j['discovery_title'] as String?,
        landmarksText: j['landmarks_text'] as String?,
        difficulty: j['difficulty'] as String?,
        searchAreaMeters: _dOrNull(j['search_area_meters']),
      );

  Map<String, dynamic> toWrite() => {
        'mission_id': missionId,
        'stop_id': stopId,
        'treasure_map_image_url': treasureMapImageUrl,
        'clue_text': clueText,
        'hint_1_text': hint1Text,
        'hint_2_text': hint2Text,
        'final_hint_text': finalHintText,
        'discovery_title': discoveryTitle,
        'landmarks_text': landmarksText,
        'difficulty': difficulty,
        'search_area_meters': searchAreaMeters,
      };
}

const List<String> kTreasureDiscoveryDifficulties = ['easy', 'medium', 'hard'];
