/// A distance-triggered narration on the way to a [MissionStop]
/// (`mission_travel_stories`, migration 0061). TRAVEL STORY and APPROACH
/// STORY (spec Phase 2/3) share this one shape — "at distance X from the
/// target stop, play narration Y" — distinguished only by [triggerType],
/// since a second near-identical table would just be a duplicate.
class MissionTravelStory {
  const MissionTravelStory({
    required this.id,
    required this.missionId,
    required this.stopId,
    this.triggerType = 'travel',
    required this.triggerDistanceMeters,
    required this.text,
    this.audioUrl,
    this.priority = 0,
    this.playOnce = true,
    this.sortOrder = 0,
  });

  final String id;
  final String missionId;
  final String stopId;

  /// 'travel' (informational, further out) | 'approach' (anticipation-
  /// building, close in) — free text, not a fixed enum, so a future mission
  /// type can introduce a new beat without a migration.
  final String triggerType;
  final double triggerDistanceMeters;
  final String text;
  final String? audioUrl;
  final int priority;
  final bool playOnce;
  final int sortOrder;

  bool get isApproach => triggerType == 'approach';

  static double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  factory MissionTravelStory.fromJson(Map<String, dynamic> j) => MissionTravelStory(
        id: (j['id'] ?? '').toString(),
        missionId: (j['mission_id'] ?? '').toString(),
        stopId: (j['stop_id'] ?? '').toString(),
        triggerType: (j['trigger_type'] ?? 'travel') as String,
        triggerDistanceMeters: _d(j['trigger_distance_meters']),
        text: (j['text'] ?? '') as String,
        audioUrl: j['audio_url'] as String?,
        priority: (j['priority'] as num?)?.toInt() ?? 0,
        playOnce: (j['play_once'] ?? true) as bool,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toWrite() => {
        'mission_id': missionId,
        'stop_id': stopId,
        'trigger_type': triggerType,
        'trigger_distance_meters': triggerDistanceMeters,
        'text': text,
        'audio_url': audioUrl,
        'priority': priority,
        'play_once': playOnce,
        'sort_order': sortOrder,
      };
}
