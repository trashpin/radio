import 'dart:math' as math;

/// Inputs to the Explorer Score for one nearby experience.
///
/// Signals that may be unknown default to a neutral 0.5 so callers can supply
/// only what they know. The score deliberately does NOT reduce to raw distance:
/// popularity, recommendation, and relevance can float a slightly-farther but
/// more interesting experience above a closer plain one, while already-visited
/// or already-narrated experiences are pushed down.
class ExplorerScoreInput {
  const ExplorerScoreInput({
    required this.distanceMeters,
    required this.radiusMeters,
    this.featured = false,
    this.recommended = false,
    this.seasonRelevance = 0.5,
    this.timeOfDayRelevance = 0.5,
    this.weatherRelevance = 0.5,
    this.guidePreference = 0.5,
    this.previouslyVisited = false,
    this.narrationAlreadyPlayed = false,
  });

  /// Distance from the visitor, in meters.
  final double distanceMeters;

  /// The active search radius, in meters (used to normalize proximity).
  final double radiusMeters;

  /// Popularity proxy — a "featured" experience is treated as more popular.
  final bool featured;

  /// Whether this is an editorially recommended stop.
  final bool recommended;

  /// 0..1 relevance to the current season / time of day / weather.
  final double seasonRelevance;
  final double timeOfDayRelevance;
  final double weatherRelevance;

  /// 0..1 match against the visitor's current guide preference.
  final double guidePreference;

  final bool previouslyVisited;
  final bool narrationAlreadyPlayed;

  /// Proximity in 0..1 (1 = right here, 0 = at/over the radius edge). Falls back
  /// to a smooth decay when the radius is unbounded.
  double get proximity {
    if (distanceMeters <= 0) return 1;
    if (radiusMeters.isFinite && radiusMeters > 0) {
      return (1 - (distanceMeters / radiusMeters)).clamp(0.0, 1.0);
    }
    return 1 / (1 + distanceMeters / 500);
  }
}

/// Weights for each Explorer Score signal (kept public so they're documented and
/// testable). Positive weights add interest; the last two subtract.
class ExplorerScoreWeights {
  const ExplorerScoreWeights();

  static const double proximity = 40;
  static const double featured = 15;
  static const double recommended = 10;
  static const double season = 8;
  static const double timeOfDay = 7;
  static const double weather = 5;
  static const double guidePreference = 10;
  static const double visitedPenalty = 12;
  static const double playedPenalty = 8;
}

/// Computes the Explorer Score (0..100) for a nearby experience.
///
/// Higher = show sooner. The most interesting nearby experiences surface first,
/// blending proximity with popularity, recommendation, seasonal/time/weather
/// relevance, and guide preference, minus penalties for things the visitor has
/// already seen or heard.
double explorerScore(ExplorerScoreInput input) {
  var score = 0.0;
  score += ExplorerScoreWeights.proximity * input.proximity;
  score += ExplorerScoreWeights.featured * (input.featured ? 1 : 0);
  score += ExplorerScoreWeights.recommended * (input.recommended ? 1 : 0);
  score += ExplorerScoreWeights.season * input.seasonRelevance.clamp(0.0, 1.0);
  score +=
      ExplorerScoreWeights.timeOfDay * input.timeOfDayRelevance.clamp(0.0, 1.0);
  score += ExplorerScoreWeights.weather * input.weatherRelevance.clamp(0.0, 1.0);
  score +=
      ExplorerScoreWeights.guidePreference * input.guidePreference.clamp(0.0, 1.0);
  if (input.previouslyVisited) score -= ExplorerScoreWeights.visitedPenalty;
  if (input.narrationAlreadyPlayed) score -= ExplorerScoreWeights.playedPenalty;
  return math.max(0.0, math.min(100.0, score));
}
