import 'package:explorer_os_mobile/features/radio_director/models/radio_director_models.dart';

/// The ExplorerOS Radio Director — a pure decision engine.
///
/// Every tick it scores the available audio events (GPS triggers, nearby POIs,
/// destination content) using a priority ladder adjusted by the guide
/// personality and the visitor's preferences, applies a silence engine so
/// music dominates and narrations never stack, honors per-visit anti-repeat,
/// and returns the single [RadioDecision] to enact.
///
/// It plays NOTHING itself: the runtime controller turns a decision into
/// commands for the Playback Manager. This class is deterministic + unit-tested.
class RadioDirector {
  const RadioDirector({this.config = const RadioDirectorConfig()});

  final RadioDirectorConfig config;

  /// Effective priority for a candidate given guide + preferences + distance.
  double score(RadioCandidate c, RadioContext ctx) {
    final base = (config.priorityOverrides[c.type] ?? c.type.basePriority)
        .toDouble();
    final mult = ctx.guide.multiplier(c.type) * ctx.preferences.scale(c.type);
    var s = base * mult;
    // A closer POI is slightly more compelling (small nudge, never reorders
    // across priority tiers).
    final d = c.distanceMeters;
    if (d != null && d > 0) {
      final proximity = (1 - (d / config.gpsTriggerDistanceMeters)).clamp(0.0, 1.0);
      s += proximity * 4;
    }
    return s;
  }

  bool _urgent(double s) => s >= config.interruptThreshold;

  double _minQuiet(RadioContext ctx) =>
      config.minQuietSeconds * ctx.playbackState.quietMultiplier();

  /// The core decision for this tick.
  RadioDecision evaluate(RadioContext ctx) {
    // Eligible candidates: not already played this visit, not disabled by prefs.
    final eligible = <(RadioCandidate, double)>[];
    for (final c in ctx.candidates) {
      if (ctx.playedKeys.contains(c.triggerKey)) continue;
      final sc = score(c, ctx);
      if (sc <= 0) continue; // disabled by preferences
      eligible.add((c, sc));
    }
    eligible.sort((a, b) => b.$2.compareTo(a.$2));

    // A narration is currently playing → never stack; only interrupt for an
    // urgent, strictly-higher-priority event (arrival/safety/approach).
    if (ctx.narrationPlaying) {
      if (eligible.isNotEmpty) {
        final (c, s) = eligible.first;
        final beatsCurrent =
            s > (ctx.currentNarrationPriority ?? 0);
        if (_urgent(s) && beatsCurrent) {
          return RadioDecision(RadioAction.playNarration,
              candidate: c, score: s, reason: 'urgent interrupt');
        }
      }
      return const RadioDecision(RadioAction.keepCurrent,
          reason: 'narration in progress');
    }

    // Not narrating: pick the top eligible event, respecting the silence window
    // (urgent events bypass it; extras must wait for quiet).
    final quiet = _minQuiet(ctx);
    for (final (c, s) in eligible) {
      if (_urgent(s)) {
        return RadioDecision(RadioAction.playNarration,
            candidate: c, score: s, reason: 'trigger/safety');
      }
      if (ctx.secondsSinceLastNarration >= quiet) {
        return RadioDecision(RadioAction.playNarration,
            candidate: c, score: s, reason: 'quiet window elapsed');
      }
      // Highest non-urgent candidate is gated by silence → let music continue.
      break;
    }

    // Nothing to say → music fills the empty time.
    return ctx.musicPlaying
        ? RadioDecision(RadioAction.keepMusic,
            reason: eligible.isEmpty
                ? 'no events'
                : 'quiet window (${quiet.round()}s)')
        : const RadioDecision(RadioAction.startMusic, reason: 'fill silence');
  }
}
