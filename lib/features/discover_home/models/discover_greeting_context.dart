/// How the local weather is framed for the opening greeting — derived from
/// the SAME [WeatherData] the radio/banter/Explore already read
/// (`currentWeatherProvider`), never a new weather system.
enum WeatherFlavor { none, good, rain }

/// A coarse recent-activity signal from `discover_interactions` (migration
/// 0053's write-only seam) — the smallest useful read of data that's already
/// being logged, not a new behavioral-personalization system.
enum BehaviorFlavor { none, gem, location, event }

/// Everything the greeting selector needs to pick a natural-sounding,
/// non-repetitive opening line. Pure data — no widgets, no providers — so
/// [DiscoverGreetingSelector] stays a plain, unit-testable function of its
/// inputs.
class DiscoverGreetingContext {
  const DiscoverGreetingContext({
    this.name,
    required this.hour,
    required this.weekday,
    this.interests = const {},
    this.weatherFlavor = WeatherFlavor.none,
    this.behaviorFlavor = BehaviorFlavor.none,
    this.hasRealLocation = false,
    this.daysSinceLastOpen,
  });

  final String? name;

  /// 0-23, local time.
  final int hour;

  /// [DateTime.weekday] — Mon=1 ... Sun=7.
  final int weekday;

  final Set<String> interests;
  final WeatherFlavor weatherFlavor;
  final BehaviorFlavor behaviorFlavor;
  final bool hasRealLocation;

  /// Null when there's no recorded previous open (e.g. first-ever launch).
  final int? daysSinceLastOpen;

  bool get isReturningVisitor =>
      daysSinceLastOpen != null && daysSinceLastOpen! >= 14;
}
