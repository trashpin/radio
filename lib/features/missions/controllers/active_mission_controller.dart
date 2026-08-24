import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_progress_repository.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_character.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_progress.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_puzzle.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_stop.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_travel_story.dart';
import 'package:explorer_os_mobile/features/missions/services/arrival_confirmer.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_story_engine.dart';

/// XP awarded for each successful QR scan — separate from
/// [Mission.completionRewardXp] (awarded once, on finishing the final
/// stop/puzzle) and a puzzle's own [MissionPuzzle.rewardXp]. Configurable-
/// in-code for now (Phase 1's "basic XP"); moving this to a per-stop admin
/// field is a natural, non-breaking follow-up.
const int _kQrScanXp = 25;

/// The result of attempting to scan a QR code — the QR scan screen reads
/// this to decide whether to transition into the Old World or show an error.
class QrScanOutcome {
  const QrScanOutcome._({required this.success, this.message, this.oldWorldId, this.missionComplete});
  factory QrScanOutcome.success({String? oldWorldId, bool missionComplete = false}) =>
      QrScanOutcome._(success: true, oldWorldId: oldWorldId, missionComplete: missionComplete);
  factory QrScanOutcome.failure(String message) => QrScanOutcome._(success: false, message: message);

  final bool success;
  final String? message;
  final String? oldWorldId;
  final bool? missionComplete;
}

class ActiveMissionState {
  const ActiveMissionState({
    this.mission,
    this.stops = const [],
    this.currentStop,
    this.currentStopStories = const [],
    this.firedIds = const {},
    this.completedStopIds = const [],
    this.revealedFactKeys = const {},
    this.solvedPuzzleIds = const {},
    this.pendingPuzzle,
    this.xp = 0,
    this.awaitingQr = false,
    this.missionComplete = false,
    this.lastDistanceMeters,
    this.lastNarrationText,
    this.loading = false,
    this.charactersById = const {},
  });

  final Mission? mission;
  final List<MissionStop> stops;
  final MissionStop? currentStop;
  final List<MissionTravelStory> currentStopStories;
  final Set<String> firedIds;
  final List<String> completedStopIds;

  /// Every [MissionCharacter], loaded once in [ActiveMissionController.
  /// startMission] — CHARACTER -> VOICE ID resolution reads this map rather
  /// than querying per story beat.
  final Map<String, MissionCharacter> charactersById;

  /// Named [MissionFact.key]s the player has actually heard so far — the
  /// player may not yet know why (spec: "the player should realize: I was
  /// supposed to remember that").
  final Set<String> revealedFactKeys;
  final Set<String> solvedPuzzleIds;

  /// Set once the final stop is complete and a mission-level puzzle exists
  /// but hasn't been solved yet — the UI shows the puzzle screen while this
  /// is non-null, instead of completing the mission immediately.
  final MissionPuzzle? pendingPuzzle;
  final int xp;

  /// The player has arrived and this stop requires a QR scan before the
  /// mission can advance.
  final bool awaitingQr;
  final bool missionComplete;
  final double? lastDistanceMeters;
  final String? lastNarrationText;
  final bool loading;

  bool get hasActiveMission => mission != null;
  bool get hasPendingPuzzle => pendingPuzzle != null;

  ActiveMissionState copyWith({
    Mission? mission,
    List<MissionStop>? stops,
    MissionStop? currentStop,
    List<MissionTravelStory>? currentStopStories,
    Set<String>? firedIds,
    List<String>? completedStopIds,
    Set<String>? revealedFactKeys,
    Set<String>? solvedPuzzleIds,
    MissionPuzzle? pendingPuzzle,
    bool clearPendingPuzzle = false,
    int? xp,
    bool? awaitingQr,
    bool? missionComplete,
    double? lastDistanceMeters,
    String? lastNarrationText,
    bool? loading,
    Map<String, MissionCharacter>? charactersById,
  }) =>
      ActiveMissionState(
        mission: mission ?? this.mission,
        stops: stops ?? this.stops,
        currentStop: currentStop ?? this.currentStop,
        currentStopStories: currentStopStories ?? this.currentStopStories,
        firedIds: firedIds ?? this.firedIds,
        completedStopIds: completedStopIds ?? this.completedStopIds,
        revealedFactKeys: revealedFactKeys ?? this.revealedFactKeys,
        solvedPuzzleIds: solvedPuzzleIds ?? this.solvedPuzzleIds,
        pendingPuzzle: clearPendingPuzzle ? null : (pendingPuzzle ?? this.pendingPuzzle),
        xp: xp ?? this.xp,
        awaitingQr: awaitingQr ?? this.awaitingQr,
        missionComplete: missionComplete ?? this.missionComplete,
        lastDistanceMeters: lastDistanceMeters ?? this.lastDistanceMeters,
        lastNarrationText: lastNarrationText ?? this.lastNarrationText,
        loading: loading ?? this.loading,
        charactersById: charactersById ?? this.charactersById,
      );
}

/// Orchestrates one active Marion County Adventures mission: watches the
/// SAME live GPS stream every other location-aware feature in this app
/// reads ([gpsControllerProvider]), runs each fix through the pure
/// [MissionStoryEngine], and drives narration playback + progress
/// persistence from the result. This is the ONLY place that decides "what
/// should happen next" — the engine stays pure/testable, the audio
/// controller stays a dumb player, and this controller is the glue.
///
/// ARCHITECTURE — four related but distinct concepts, kept deliberately
/// separate so a location can be "real" without being "active":
///   1. LOCATION RECORD — a permanent row in `locations`/[MasterLocation].
///      Exists independently of any mission; never created, modified, or
///      deleted by anything in this file.
///   2. MISSION STOP — a [MissionStop] row: a location borrowed by one
///      specific mission's sequence (optionally linked back to a location
///      record via [MissionStop.locationId] for shared photos/description).
///   3. ACTIVE MISSION GEOFENCE — exactly the ONE [MissionStop] held in
///      `state.currentStop`. [_onFix] only ever evaluates that single stop
///      (see [MissionStoryEngine.evaluate]'s own doc) — never a list of
///      every stop in the mission, and never every location in the county.
///      This is what makes "only the current stop can trigger mission
///      events" true by construction, not a runtime check that could be
///      forgotten. [_completeStop] is the only place `currentStop` changes
///      — it REPLACES the field rather than adding to a collection, which
///      is the "deactivate current geofence, activate next" transition the
///      spec asks for: there is never a moment where two stops are active.
///   4. OPTIONAL DISCOVERY — everything else nearby. See
///      `journeyNearbyLocationsProvider`, which reads location records
///      directly for map display and is never wired into this controller
///      or [MissionStoryEngine] — structurally incapable of firing a
///      mission event, no matter how close the player gets to one.
class ActiveMissionController extends Notifier<ActiveMissionState> {
  static const _engine = MissionStoryEngine();
  final _arrivalConfirmer = ArrivalConfirmer();
  MissionProgress? _progress;

  @override
  ActiveMissionState build() {
    ref.listen<TravelContext>(gpsControllerProvider, (_, ctx) => _onFix(ctx));
    return const ActiveMissionState();
  }

  Future<void> startMission(Mission mission) async {
    state = state.copyWith(loading: true);
    final repo = ref.read(missionRepositoryProvider);
    final stops = await repo.stopsForMission(mission.id);
    if (stops.isEmpty) {
      state = const ActiveMissionState();
      return;
    }

    final progressRepo = ref.read(missionProgressRepositoryProvider);
    final existing = await progressRepo.forMission(mission.id);
    final progress = existing ??
        await progressRepo.startOrResume(mission.id, stops.first.id) ??
        MissionProgress(
          id: '',
          userId: '',
          missionId: mission.id,
          currentStopId: stops.first.id,
          status: 'in_progress',
        );
    _progress = progress;

    final currentStopId = progress.currentStopId ?? stops.first.id;
    final currentStop = stops.firstWhere(
      (s) => s.id == currentStopId,
      orElse: () => stops.first,
    );
    final stories = await repo.travelStoriesForStop(currentStop.id);
    final firedIds = progress.firedContentIds.toSet();
    // Loaded once per mission start, not per story beat -- CHARACTER ->
    // VOICE ID resolution in [_fireTravelStory]/[_fireArrival] is then a
    // plain in-memory map lookup, adding no latency to the GPS hot path.
    final characters = await repo.allCharacters();
    final charactersById = {for (final c in characters) c.id: c};

    // `awaiting_qr` has no column of its own — it's derived from data
    // already persisted. Arrival fired for this stop, but the stop isn't
    // in `completedStopIds` yet, means exactly one thing: the player
    // arrived and the app was closed/restarted before a QR scan completed
    // it (mission_progress.fired_content_ids is written the instant
    // arrival narration starts, well before a scan can happen). Without
    // this, resuming would silently drop back to `awaitingQr: false` with
    // arrival already marked fired, so the engine would never re-evaluate
    // this stop again and the player would be stuck with no "Scan QR"
    // button and no way forward.
    final alreadyArrived = firedIds.contains(missionArrivalFiredKey(currentStop.id)) &&
        !progress.completedStopIds.contains(currentStop.id);

    state = ActiveMissionState(
      mission: mission,
      stops: stops,
      currentStop: currentStop,
      currentStopStories: stories,
      firedIds: firedIds,
      completedStopIds: progress.completedStopIds,
      revealedFactKeys: progress.revealedFactKeys.toSet(),
      solvedPuzzleIds: progress.solvedPuzzleIds.toSet(),
      xp: progress.xp,
      awaitingQr: alreadyArrived && currentStop.requiresQr,
      loading: false,
      charactersById: charactersById,
    );
    // The opening narration is spoken on the Adventure Introduction screen,
    // BEFORE the player ever reaches this GPS-tracking player (spec: "they
    // should first be pulled into a story," not shown a map immediately) —
    // never replayed here, so it's heard exactly once per fresh start.

    if (alreadyArrived && !currentStop.requiresQr) {
      // Same crash-window case as above, but for a stop that never needed
      // a QR scan in the first place: arrival should have completed it
      // immediately (see [_fireArrival]) and almost always does, but a
      // restart landing in the narrow gap between marking arrival fired
      // and marking the stop complete would otherwise strand the player
      // exactly like the QR case. Self-heals on resume.
      await _completeStop(currentStop);
    }
  }

  void _onFix(TravelContext ctx) {
    final loc = ctx.location;
    final stop = state.currentStop;
    if (loc == null ||
        stop == null ||
        state.awaitingQr ||
        state.missionComplete ||
        state.hasPendingPuzzle) {
      return;
    }

    final isNarrationPlaying = ref.read(missionAudioControllerProvider).isActive;
    final result = _engine.evaluate(
      lat: loc.latitude,
      lng: loc.longitude,
      targetStop: stop,
      stories: state.currentStopStories,
      alreadyFiredIds: state.firedIds,
      isNarrationPlaying: isNarrationPlaying,
    );

    state = state.copyWith(lastDistanceMeters: result.distanceMeters);

    // Tracked on every fix (not just when the engine says "arrive") so a
    // fix that drifts back outside the radius resets the streak — the
    // player must be continuously inside, not just inside on one noisy
    // sample. See [ArrivalConfirmer]'s own doc for why this exists.
    final insideArrivalRadius = result.distanceMeters <= stop.arrivalRadiusMeters;
    final confirmedArrival = _arrivalConfirmer.confirm(stop.id, insideArrivalRadius);

    switch (result.action) {
      case MissionEngineAction.none:
        return;
      case MissionEngineAction.playTravelStory:
        _fireTravelStory(result.story!);
      case MissionEngineAction.arrive:
        if (confirmedArrival) _fireArrival(result.stop!);
      // else: inside the radius on this fix, but not yet on enough
      // consecutive fixes to rule out GPS drift — wait for the next fix
      // rather than firing arrival narration/completion early.
    }
  }

  /// CHARACTER -> VOICE ID: the character's own voice always wins over any
  /// free-text voice override on the scene itself — a voice is never
  /// re-picked per scene once a character is assigned. Falls back to
  /// [fallbackVoiceId] (or the shared global default, null) when no
  /// character is linked, so content with no character record yet keeps
  /// working exactly as before.
  String? _voiceIdFor(String? characterId, String? fallbackVoiceId) {
    if (characterId != null) {
      final voice = state.charactersById[characterId]?.voiceId;
      if ((voice ?? '').trim().isNotEmpty) return voice;
    }
    return fallbackVoiceId;
  }

  Future<void> _fireTravelStory(MissionTravelStory story) async {
    _markFired(story.id);
    if (story.revealsFactKeys.isNotEmpty) _markFactsRevealed(story.revealsFactKeys);
    state = state.copyWith(lastNarrationText: story.text);
    await _speak(
      subjectId: story.id,
      kind: story.triggerType,
      text: story.text,
      preRecordedUrl: story.audioUrl,
      title: state.mission?.title ?? 'Adventure',
      voiceId: _voiceIdFor(story.characterId, story.voiceId),
    );
  }

  Future<void> _fireArrival(MissionStop stop) async {
    _markFired(missionArrivalFiredKey(stop.id));
    final text = (stop.arrivalNarrationText ?? '').trim().isNotEmpty
        ? stop.arrivalNarrationText!
        : "You've arrived at ${stop.title}. Look around for your next discovery.";
    state = state.copyWith(lastNarrationText: text);
    await _speak(
      subjectId: missionArrivalFiredKey(stop.id),
      kind: 'arrival',
      text: text,
      preRecordedUrl: stop.arrivalNarrationAudioUrl,
      title: state.mission?.title ?? 'Adventure',
      voiceId: _voiceIdFor(stop.arrivalCharacterId, null),
    );

    if (stop.requiresQr) {
      state = state.copyWith(awaitingQr: true);
    } else {
      await _completeStop(stop);
    }
  }

  /// Called by the Old World screen once its narration is known (facts are
  /// revealed the moment the content is shown, not gated on audio actually
  /// finishing — matches how travel stories reveal facts the instant they
  /// fire).
  void markFactsRevealed(List<String> keys) {
    if (keys.isEmpty) return;
    _markFactsRevealed(keys);
  }

  void _markFactsRevealed(List<String> keys) {
    state = state.copyWith(revealedFactKeys: {...state.revealedFactKeys, ...keys});
    _persist();
  }

  Future<void> _speak({
    required String subjectId,
    required String kind,
    required String text,
    String? preRecordedUrl,
    required String title,
    String? voiceId,
  }) async {
    if (text.trim().isEmpty && (preRecordedUrl ?? '').trim().isEmpty) return;
    String? audioUrl = preRecordedUrl;
    if ((audioUrl ?? '').trim().isEmpty) {
      final result = await ref
          .read(missionNarrationServiceProvider)
          .requestFor(subjectId: subjectId, kind: kind, text: text, voiceId: voiceId);
      audioUrl = result?.audioUrl;
    }
    await ref.read(missionAudioControllerProvider.notifier).play(
          title: title,
          audioUrl: audioUrl,
          spokenText: text,
        );
  }

  void _markFired(String id) {
    state = state.copyWith(firedIds: {...state.firedIds, id});
    _persist();
  }

  /// Attempts to resolve and act on a scanned QR payload (spec Phase 4's
  /// 8-step checklist): identify the portal, confirm it belongs to the
  /// current mission stage (or is globally reusable), verify GPS proximity
  /// when required, record the discovery, award XP, and unlock the Old
  /// World — all before the caller ever navigates to the reveal screen.
  Future<QrScanOutcome> onQrScanned(String code, {double? lat, double? lng}) async {
    final stop = state.currentStop;
    if (stop == null || !state.awaitingQr) {
      return QrScanOutcome.failure("This mission isn't expecting a QR scan right now.");
    }

    final portal = await ref.read(missionRepositoryProvider).portalByCode(code);
    if (portal == null || !portal.active) {
      return QrScanOutcome.failure('This QR code isn\'t recognized.');
    }
    if (!portal.isGlobal && portal.missionStopId != null && portal.missionStopId != stop.id) {
      return QrScanOutcome.failure("This QR code belongs to a different part of the adventure.");
    }

    if (portal.requiresGpsProximity && lat != null && lng != null) {
      final distance = GeoMath.distanceMeters(lat, lng, stop.latitude, stop.longitude);
      final grace = stop.arrivalRadiusMeters * 3;
      if (distance > grace) {
        return QrScanOutcome.failure("You don't seem to be at the right location yet.");
      }
    }

    final oldWorldId = portal.oldWorldId ?? stop.oldWorldId;
    state = state.copyWith(xp: state.xp + _kQrScanXp);
    final missionComplete = await _completeStop(stop, oldWorldId: oldWorldId);
    return QrScanOutcome.success(oldWorldId: oldWorldId, missionComplete: missionComplete);
  }

  /// Marks [stop] complete, advances to its next stop (preferring an
  /// explicit `next_stop_id`, falling back to the next sequence number), or
  /// -- when none remains -- checks for a mission-level puzzle before
  /// finishing. Returns true if the mission just completed outright (no
  /// puzzle, or already solved on a previous run).
  ///
  /// This is the whole "deactivate current geofence, activate next
  /// geofence" transition: `state.currentStop` is REPLACED with [next] in
  /// one atomic state update, never appended to a list of active stops.
  /// Between one call to [_onFix] and the next, there is no window where
  /// both the completed stop and the next stop are simultaneously active.
  Future<bool> _completeStop(MissionStop stop, {String? oldWorldId}) async {
    final completed = {...state.completedStopIds, stop.id}.toList();

    MissionStop? next;
    if (stop.nextStopId != null) {
      next = state.stops.where((s) => s.id == stop.nextStopId).firstOrNull;
    }
    next ??= state.stops.where((s) => s.sequence == stop.sequence + 1).firstOrNull;

    if (next == null) {
      state = state.copyWith(completedStopIds: completed, awaitingQr: false);
      return _checkFinalPuzzleOrComplete();
    }

    final stories = await ref.read(missionRepositoryProvider).travelStoriesForStop(next.id);
    state = state.copyWith(
      completedStopIds: completed,
      currentStop: next,
      currentStopStories: stories,
      awaitingQr: false,
    );
    await _persist();
    return false;
  }

  Future<bool> _checkFinalPuzzleOrComplete() async {
    final mission = state.mission;
    if (mission == null) return false;
    final puzzle = await ref.read(missionRepositoryProvider).finalPuzzleForMission(mission.id);
    if (puzzle != null && !state.solvedPuzzleIds.contains(puzzle.id)) {
      state = state.copyWith(pendingPuzzle: puzzle);
      await _persist();
      return false;
    }
    return _finalizeMissionComplete();
  }

  /// Checks [answer] against the pending final puzzle (spec: a simple,
  /// honest string match, not an AI grader). On success, awards the
  /// puzzle's own XP and completes the mission; on failure, the pending
  /// puzzle stays in place so the player can try again.
  bool solvePuzzle(String answer) {
    final puzzle = state.pendingPuzzle;
    if (puzzle == null) return false;
    if (!puzzle.checkAnswer(answer)) return false;

    state = state.copyWith(
      solvedPuzzleIds: {...state.solvedPuzzleIds, puzzle.id},
      xp: state.xp + puzzle.rewardXp,
      clearPendingPuzzle: true,
    );
    _finalizeMissionComplete();
    return true;
  }

  bool _finalizeMissionComplete() {
    final mission = state.mission;
    state = state.copyWith(
      missionComplete: true,
      xp: state.xp + (mission?.completionRewardXp ?? 0),
    );
    _persist(status: 'completed');
    return true;
  }

  Future<void> _persist({String? status}) async {
    final base = _progress;
    if (base == null || base.id.isEmpty) return;
    final updated = base.copyWith(
      currentStopId: state.currentStop?.id,
      completedStopIds: state.completedStopIds,
      firedContentIds: state.firedIds.toList(),
      revealedFactKeys: state.revealedFactKeys.toList(),
      solvedPuzzleIds: state.solvedPuzzleIds.toList(),
      xp: state.xp,
      status: status ?? base.status,
      completedAt: status == 'completed' ? DateTime.now().toUtc() : base.completedAt,
    );
    _progress = updated;
    await ref.read(missionProgressRepositoryProvider).save(updated);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

final activeMissionControllerProvider =
    NotifierProvider<ActiveMissionController, ActiveMissionState>(ActiveMissionController.new);
