import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_stop.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_travel_story.dart';

enum MissionEngineAction { none, playTravelStory, arrive }

/// What the engine wants to happen this tick — at most ONE action, never
/// several (spec: "Prevent multiple stories from overlapping").
class MissionEngineResult {
  const MissionEngineResult._(this.action, this.distanceMeters, {this.story, this.stop});

  factory MissionEngineResult.none({required double distanceMeters}) =>
      MissionEngineResult._(MissionEngineAction.none, distanceMeters);

  factory MissionEngineResult.playStory(MissionTravelStory story, {required double distanceMeters}) =>
      MissionEngineResult._(MissionEngineAction.playTravelStory, distanceMeters, story: story);

  factory MissionEngineResult.arrive(MissionStop stop, {required double distanceMeters}) =>
      MissionEngineResult._(MissionEngineAction.arrive, distanceMeters, stop: stop);

  final MissionEngineAction action;
  final double distanceMeters;
  final MissionTravelStory? story;
  final MissionStop? stop;
}

/// The synthetic "already fired" key for a stop's arrival beat — arrival
/// isn't a `mission_travel_stories` row, so it needs its own id shape in the
/// same fired-content set.
String missionArrivalFiredKey(String stopId) => 'arrival:$stopId';

/// Pure, unit-testable distance-based trigger selection (spec Phase 2/3).
/// Reuses [GeoMath] and whatever live GPS fix the caller already has — this
/// is deliberately NOT a second GPS/geofencing system, just a narrative
/// layer over the player's existing position stream and the existing
/// great-circle distance utility every other feature in this app uses.
class MissionStoryEngine {
  const MissionStoryEngine();

  /// Evaluates one GPS fix against the CURRENT target stop — and only that
  /// stop. There is no overload that accepts a list of stops or locations:
  /// the caller ([ActiveMissionController]) always passes exactly one
  /// [MissionStop] (its `state.currentStop`) and that stop's own stories,
  /// which is what makes it structurally impossible for any other Marion
  /// County location — including other stops in the SAME mission — to
  /// trigger a story or arrival event while the player travels toward this
  /// one (see the "ACTIVE MISSION GEOFENCE" note on
  /// [ActiveMissionController]'s own doc comment).
  ///
  /// - Never interrupts a narration already playing ([isNarrationPlaying]).
  /// - Arrival always takes priority over any travel/approach story once
  ///   inside [MissionStop.arrivalRadiusMeters].
  /// - Otherwise the nearest not-yet-fired story whose trigger distance the
  ///   player has crossed wins, ties broken by [MissionTravelStory.priority]
  ///   then by the smallest trigger distance (the closest narrative beat).
  /// - [alreadyFiredIds] is the union of this session's in-memory fired set
  ///   and the player's persisted `mission_progress.fired_content_ids` —
  ///   the caller owns merging those; this engine only ever reads the set.
  MissionEngineResult evaluate({
    required double lat,
    required double lng,
    required MissionStop targetStop,
    required List<MissionTravelStory> stories,
    required Set<String> alreadyFiredIds,
    bool isNarrationPlaying = false,
  }) {
    final distance = GeoMath.distanceMeters(
        lat, lng, targetStop.latitude, targetStop.longitude);

    if (isNarrationPlaying) {
      return MissionEngineResult.none(distanceMeters: distance);
    }

    if (distance <= targetStop.arrivalRadiusMeters) {
      final key = missionArrivalFiredKey(targetStop.id);
      if (!alreadyFiredIds.contains(key)) {
        return MissionEngineResult.arrive(targetStop, distanceMeters: distance);
      }
      return MissionEngineResult.none(distanceMeters: distance);
    }

    final candidates = stories
        .where((s) => !alreadyFiredIds.contains(s.id) && distance <= s.triggerDistanceMeters)
        .toList()
      ..sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority);
        if (byPriority != 0) return byPriority;
        return a.triggerDistanceMeters.compareTo(b.triggerDistanceMeters);
      });

    if (candidates.isEmpty) return MissionEngineResult.none(distanceMeters: distance);
    return MissionEngineResult.playStory(candidates.first, distanceMeters: distance);
  }
}
