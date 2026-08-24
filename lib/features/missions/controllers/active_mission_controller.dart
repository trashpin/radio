import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/missions/controllers/mission_audio_controller.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_progress_repository.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_progress.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_stop.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_travel_story.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_narration_service.dart';
import 'package:explorer_os_mobile/features/missions/services/mission_story_engine.dart';

/// XP awarded for each successful QR scan — separate from
/// [Mission.completionRewardXp], which is awarded once, on finishing the
/// final stop. Configurable-in-code for now (Phase 1's "basic XP"); moving
/// this to a per-stop admin field is a natural, non-breaking follow-up.
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
    this.xp = 0,
    this.awaitingQr = false,
    this.missionComplete = false,
    this.lastDistanceMeters,
    this.lastNarrationText,
    this.loading = false,
  });

  final Mission? mission;
  final List<MissionStop> stops;
  final MissionStop? currentStop;
  final List<MissionTravelStory> currentStopStories;
  final Set<String> firedIds;
  final List<String> completedStopIds;
  final int xp;

  /// The player has arrived and this stop requires a QR scan before the
  /// mission can advance.
  final bool awaitingQr;
  final bool missionComplete;
  final double? lastDistanceMeters;
  final String? lastNarrationText;
  final bool loading;

  bool get hasActiveMission => mission != null;

  ActiveMissionState copyWith({
    Mission? mission,
    List<MissionStop>? stops,
    MissionStop? currentStop,
    List<MissionTravelStory>? currentStopStories,
    Set<String>? firedIds,
    List<String>? completedStopIds,
    int? xp,
    bool? awaitingQr,
    bool? missionComplete,
    double? lastDistanceMeters,
    String? lastNarrationText,
    bool? loading,
  }) =>
      ActiveMissionState(
        mission: mission ?? this.mission,
        stops: stops ?? this.stops,
        currentStop: currentStop ?? this.currentStop,
        currentStopStories: currentStopStories ?? this.currentStopStories,
        firedIds: firedIds ?? this.firedIds,
        completedStopIds: completedStopIds ?? this.completedStopIds,
        xp: xp ?? this.xp,
        awaitingQr: awaitingQr ?? this.awaitingQr,
        missionComplete: missionComplete ?? this.missionComplete,
        lastDistanceMeters: lastDistanceMeters ?? this.lastDistanceMeters,
        lastNarrationText: lastNarrationText ?? this.lastNarrationText,
        loading: loading ?? this.loading,
      );
}

/// Orchestrates one active Marion County Adventures mission: watches the
/// SAME live GPS stream every other location-aware feature in this app
/// reads ([gpsControllerProvider]), runs each fix through the pure
/// [MissionStoryEngine], and drives narration playback + progress
/// persistence from the result. This is the ONLY place that decides "what
/// should happen next" — the engine stays pure/testable, the audio
/// controller stays a dumb player, and this controller is the glue.
class ActiveMissionController extends Notifier<ActiveMissionState> {
  static const _engine = MissionStoryEngine();
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

    final isFreshStart = progress.completedStopIds.isEmpty && progress.firedContentIds.isEmpty;

    state = ActiveMissionState(
      mission: mission,
      stops: stops,
      currentStop: currentStop,
      currentStopStories: stories,
      firedIds: progress.firedContentIds.toSet(),
      completedStopIds: progress.completedStopIds,
      xp: progress.xp,
      loading: false,
    );

    if (isFreshStart && mission.hasOpeningNarration) {
      await _speak(
        subjectId: 'opening:${mission.id}',
        kind: 'opening',
        text: mission.openingNarrationText ?? '',
        preRecordedUrl: mission.openingNarrationAudioUrl,
        title: mission.title,
      );
    }
  }

  void _onFix(TravelContext ctx) {
    final loc = ctx.location;
    final stop = state.currentStop;
    if (loc == null || stop == null || state.awaitingQr || state.missionComplete) return;

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

    switch (result.action) {
      case MissionEngineAction.none:
        return;
      case MissionEngineAction.playTravelStory:
        _fireTravelStory(result.story!);
      case MissionEngineAction.arrive:
        _fireArrival(result.stop!);
    }
  }

  Future<void> _fireTravelStory(MissionTravelStory story) async {
    _markFired(story.id);
    state = state.copyWith(lastNarrationText: story.text);
    await _speak(
      subjectId: story.id,
      kind: story.triggerType,
      text: story.text,
      preRecordedUrl: story.audioUrl,
      title: state.mission?.title ?? 'Adventure',
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
    );

    if (stop.requiresQr) {
      state = state.copyWith(awaitingQr: true);
    } else {
      await _completeStop(stop);
    }
  }

  Future<void> _speak({
    required String subjectId,
    required String kind,
    required String text,
    String? preRecordedUrl,
    required String title,
  }) async {
    if (text.trim().isEmpty && (preRecordedUrl ?? '').trim().isEmpty) return;
    String? audioUrl = preRecordedUrl;
    if ((audioUrl ?? '').trim().isEmpty) {
      final result = await ref
          .read(missionNarrationServiceProvider)
          .requestFor(subjectId: subjectId, kind: kind, text: text);
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
  /// finishes the mission if none remains. Returns true if the mission just
  /// completed.
  Future<bool> _completeStop(MissionStop stop, {String? oldWorldId}) async {
    final completed = {...state.completedStopIds, stop.id}.toList();

    MissionStop? next;
    if (stop.nextStopId != null) {
      next = state.stops.where((s) => s.id == stop.nextStopId).firstOrNull;
    }
    next ??= state.stops.where((s) => s.sequence == stop.sequence + 1).firstOrNull;

    if (next == null) {
      final mission = state.mission;
      final finalXp = state.xp + (mission?.completionRewardXp ?? 0);
      state = state.copyWith(
        completedStopIds: completed,
        awaitingQr: false,
        missionComplete: true,
        xp: finalXp,
      );
      await _persist(status: 'completed');
      return true;
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

  Future<void> _persist({String? status}) async {
    final base = _progress;
    if (base == null || base.id.isEmpty) return;
    final updated = base.copyWith(
      currentStopId: state.currentStop?.id,
      completedStopIds: state.completedStopIds,
      firedContentIds: state.firedIds.toList(),
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
