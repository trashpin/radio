import 'package:explorer_os_mobile/features/copilot/models/copilot_priority.dart';

/// Every kind of thing the Copilot Brain can be told about. Reserves
/// [stopSignAhead] for a future navigation phase — no stop-sign dataset
/// exists anywhere the app can reach today, so nothing ever fires it; it
/// stays here, mapped to [CopilotPriorityTier.safety], purely so a future
/// data source has a slot ready to plug into without touching this enum.
enum CopilotEventType {
  tripStarted,
  enteringTown,
  enteringCounty,
  approachingManeuver,
  missedTurn,
  recalculating,
  arrived,
  approachingInterestingLocation,
  whatIsThatConfirmed,
  stopSignAhead,
}

extension CopilotEventTypeTier on CopilotEventType {
  CopilotPriorityTier get defaultTier => switch (this) {
        CopilotEventType.stopSignAhead => CopilotPriorityTier.safety,
        CopilotEventType.approachingManeuver => CopilotPriorityTier.navigation,
        CopilotEventType.missedTurn => CopilotPriorityTier.navigation,
        CopilotEventType.recalculating => CopilotPriorityTier.navigation,
        CopilotEventType.arrived => CopilotPriorityTier.personality,
        CopilotEventType.tripStarted => CopilotPriorityTier.personality,
        CopilotEventType.enteringTown => CopilotPriorityTier.personality,
        CopilotEventType.enteringCounty => CopilotPriorityTier.personality,
        CopilotEventType.approachingInterestingLocation =>
          CopilotPriorityTier.informational,
        CopilotEventType.whatIsThatConfirmed => CopilotPriorityTier.personality,
      };
}

/// One meaningful thing that happened, handed to `CopilotBrain.decide()`.
/// Carries only what's needed to decide whether to speak and what facts the
/// AI is allowed to use — never raw GPS/geometry, which stays in the
/// GPS/navigation layers that produced this event.
class CopilotEvent {
  const CopilotEvent({
    required this.type,
    this.placeName,
    this.placeId,
    this.typeLabel,
    this.distanceMeters,
    this.coreText,
    this.facts = const [],
  });

  final CopilotEventType type;
  final String? placeName;
  final String? placeId;

  /// The location's own type label (e.g. "Spring", "Museum", "Restaurant")
  /// when this event is about a specific place — reused as-is from the
  /// existing `LocationType.label`, never a parallel taxonomy.
  final String? typeLabel;
  final double? distanceMeters;

  /// For safety/navigation events: the deterministic, already-correct
  /// instruction (Google's own maneuver wording, or a short fixed template
  /// for missed-turn/recalculating/arrival) that must always be spoken
  /// exactly as given — the AI may only add a short remark alongside it,
  /// never replace or reword it.
  final String? coreText;

  /// Verified facts available for this event (county facts, a place's own
  /// description) — the ONLY facts the AI is allowed to draw on.
  final List<String> facts;

  CopilotPriorityTier get tier => type.defaultTier;

  /// A stable key for per-trip anti-repeat — two events sharing a key won't
  /// both speak in the same trip/session (see `CopilotSessionMemory`).
  String get dedupeKey => switch (type) {
        CopilotEventType.approachingManeuver =>
          'maneuver:${placeName ?? ''}:${coreText ?? ''}',
        CopilotEventType.approachingInterestingLocation =>
          'place:${placeId ?? placeName ?? ''}',
        CopilotEventType.enteringTown => 'town:${placeName ?? ''}',
        CopilotEventType.enteringCounty => 'county:${placeName ?? ''}',
        CopilotEventType.whatIsThatConfirmed =>
          'wit:${DateTime.now().millisecondsSinceEpoch}', // always fresh
        _ => type.name,
      };
}
