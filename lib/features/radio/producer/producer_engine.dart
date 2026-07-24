import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_queue_item.dart';
import 'package:explorer_os_mobile/features/radio/producer/decision_reason.dart';
import 'package:explorer_os_mobile/features/radio/producer/playback_decision.dart';
import 'package:explorer_os_mobile/features/radio/producer/producer_context.dart';
import 'package:explorer_os_mobile/features/radio/producer/producer_rules.dart';

/// The ExplorerOS AI Producer — decides WHAT should play next.
///
/// It sits one level above the Radio Engine's mechanics: given a rich
/// [ProducerContext] (station, location, destination/park/state/route, time,
/// weather, season, preferences, history, upcoming GPS stories, queue length),
/// it applies a fixed priority ladder and the tunable [ProducerRules] to return
/// a single [PlaybackDecision]. It NEVER plays audio and holds no playback
/// state — it is a pure function of context (plus a monotonic id counter), which
/// makes every decision explainable and unit-testable.
///
/// Decision priority ladder (highest first):
///   1. Emergency            — overrides everything
///   2. Safety               — overrides all non-emergency
///   3. Navigation           — time-critical turn prompts (GPS-ready)
///   4. Scheduled Story      — story due per cadence
///   5. Upcoming Attraction  — approaching a location story (GPS-ready)
///   6. Station Identification
///   7. Music (location-aware)
///   8. Ambient
///
/// The engine executes the decision (queue insertion, interruption, resume);
/// this class only chooses. GPS inputs are placeholders today.
class ProducerEngine {
  ProducerEngine({this.rules = const ProducerRules()});

  final ProducerRules rules;
  int _sequence = 0;

  /// Returns the next decision by walking the priority ladder top-down and
  /// stopping at the first eligible tier.
  PlaybackDecision determineNextItem(ProducerContext ctx) {
    // 1. Emergency — always wins, always interrupts.
    if (ctx.pendingEmergency != null) {
      return _decide(ctx, ctx.pendingEmergency!, DecisionReason.emergency,
          interrupts: true, force: true);
    }

    // 2. Safety — wins over everything except emergency.
    if (ctx.pendingSafety != null) {
      return _decide(ctx, ctx.pendingSafety!, DecisionReason.safety,
          interrupts: true, force: true);
    }

    // 3. Navigation — time-critical (GPS-ready).
    if (ctx.pendingNavigation != null) {
      return _decide(ctx, ctx.pendingNavigation!, DecisionReason.navigation,
          interrupts: true);
    }

    // 4. Scheduled story — due per cadence.
    if (shouldInsertStory(ctx)) {
      return _decide(ctx, ctx.scheduledStory!, DecisionReason.scheduledStory,
          interrupts: true);
    }

    // 5. Upcoming attraction — approaching a location story (GPS-ready).
    if (ctx.upcomingAttraction != null && _allowed(ctx, ctx.upcomingAttraction!)) {
      return _decide(
          ctx, ctx.upcomingAttraction!, DecisionReason.upcomingAttraction,
          interrupts: true);
    }

    // 6. Station identification — due per cadence.
    if (shouldPlayStationID(ctx)) {
      return _decide(
          ctx, ctx.stationId!, DecisionReason.stationIdentification,
          interrupts: false);
    }

    // 7. Music — the baseline; location-aware when we have location context.
    if (ctx.nextMusic != null && _allowed(ctx, ctx.nextMusic!)) {
      final reason = shouldPlayLocationMusic(ctx)
          ? DecisionReason.locationMusic
          : DecisionReason.music;
      return _decide(ctx, ctx.nextMusic!, reason, interrupts: false);
    }

    // 8. Ambient — fills silence when allowed.
    if (rules.allowAmbientWhenIdle &&
        ctx.preferences.ambientEnabled &&
        ctx.ambient != null &&
        _allowed(ctx, ctx.ambient!)) {
      return _decide(ctx, ctx.ambient!, DecisionReason.ambient,
          interrupts: false);
    }

    return PlaybackDecision.nothing();
  }

  /// Whether the currently-playing item should be interrupted right now, i.e.
  /// there is a higher-priority eligible candidate and the current item allows
  /// interruption.
  bool shouldInterrupt(ProducerContext ctx) {
    final current = ctx.currentSegment;
    if (current == null) return false;
    final candidate = _highestInterruptCandidate(ctx);
    if (candidate == null) return false;
    final overrides = candidate.priority.isHigherThan(current.priority);
    // Emergency/safety override even non-interruptible items.
    final isCritical = candidate == ctx.pendingEmergency ||
        candidate == ctx.pendingSafety;
    return overrides && (isCritical || current.interruptible);
  }

  /// Whether previously-paused music should resume: something is stashed, and no
  /// higher-priority candidate is waiting.
  bool shouldResumeMusic(ProducerContext ctx) {
    if (!ctx.hasPausedMusic) return false;
    if (_highestInterruptCandidate(ctx) != null) return false;
    return ctx.currentSegment == null || ctx.currentSegment!.resumeAfter;
  }

  /// Whether a story is due: enabled, available, and the cadence has elapsed.
  bool shouldInsertStory(ProducerContext ctx) {
    return ctx.preferences.narrationsEnabled &&
        ctx.scheduledStory != null &&
        _allowed(ctx, ctx.scheduledStory!) &&
        ctx.tracksSinceStory >= rules.storyEveryTracks;
  }

  /// Whether a station identification is due.
  bool shouldPlayStationID(ProducerContext ctx) {
    return ctx.preferences.announcementsEnabled &&
        ctx.stationId != null &&
        _allowed(ctx, ctx.stationId!) &&
        ctx.tracksSinceStationId >= rules.stationIdEveryTracks;
  }

  /// Whether the next music should be treated as location/context-aware.
  /// GPS-ready: true when location context exists and the feature is enabled.
  bool shouldPlayLocationMusic(ProducerContext ctx) {
    return rules.enableLocationMusic &&
        ctx.nextMusic != null &&
        ctx.hasLocationContext;
  }

  // --- Internals -----------------------------------------------------------

  /// The highest-priority candidate among the interrupting tiers that is
  /// currently eligible (used by [shouldInterrupt]).
  AudioSegment? _highestInterruptCandidate(ProducerContext ctx) {
    final candidates = <AudioSegment>[
      if (ctx.pendingEmergency != null) ctx.pendingEmergency!,
      if (ctx.pendingSafety != null) ctx.pendingSafety!,
      if (ctx.pendingNavigation != null) ctx.pendingNavigation!,
      if (shouldInsertStory(ctx)) ctx.scheduledStory!,
      if (ctx.upcomingAttraction != null && _allowed(ctx, ctx.upcomingAttraction!))
        ctx.upcomingAttraction!,
    ];
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.priority.rank.compareTo(b.priority.rank));
    return candidates.first;
  }

  /// Preference/tag gating (safety-critical tiers bypass this via [force]).
  bool _allowed(ProducerContext ctx, AudioSegment segment) {
    if (!rules.respectUserPreferences) return true;
    return ctx.preferences.allowsTags(segment.tags);
  }

  PlaybackDecision _decide(
    ProducerContext ctx,
    AudioSegment segment,
    DecisionReason reason, {
    required bool interrupts,
    bool force = false,
  }) {
    final current = ctx.currentSegment;
    final interrupt = interrupts &&
        (current == null || segment.priority.isHigherThan(current.priority)) &&
        (force || (current?.interruptible ?? true));

    return PlaybackDecision(
      reason: reason,
      item: _wrap(segment, reason),
      interrupt: interrupt,
      resumeMusic: segment.resumeAfter,
      explanation: _explain(ctx, reason),
    );
  }

  PlaybackQueueItem _wrap(AudioSegment segment, DecisionReason reason) {
    return PlaybackQueueItem(
      id: 'producer:${_sequence++}',
      segment: segment,
      origin: _originFor(reason),
      enqueuedAt: DateTime.now(),
    );
  }

  QueueOrigin _originFor(DecisionReason reason) {
    switch (reason) {
      case DecisionReason.emergency:
      case DecisionReason.safety:
      case DecisionReason.navigation:
        return QueueOrigin.insertPriority;
      case DecisionReason.scheduledStory:
        return QueueOrigin.scheduledStory;
      case DecisionReason.upcomingAttraction:
        return QueueOrigin.gps;
      case DecisionReason.stationIdentification:
        return QueueOrigin.scheduledAnnouncement;
      case DecisionReason.resumeMusic:
        return QueueOrigin.resume;
      case DecisionReason.music:
      case DecisionReason.locationMusic:
      case DecisionReason.ambient:
      case DecisionReason.nothingToPlay:
        return QueueOrigin.enqueue;
    }
  }

  String _explain(ProducerContext ctx, DecisionReason reason) {
    final where = ctx.parkId != null
        ? ' (park ${ctx.parkId})'
        : ctx.stateName != null
            ? ' (${ctx.stateName})'
            : '';
    return '${reason.description} '
        '[${ctx.resolvedTimeOfDay.name}, ${ctx.resolvedSeason.name}$where]';
  }
}

/// Provides the AI Producer. Override with custom [ProducerRules] per station.
final producerEngineProvider = Provider<ProducerEngine>((ref) {
  return ProducerEngine();
});
