/// Driving vs Walking tour — same mechanism (GPS-triggered narration as the
/// traveler nears each stop), different proximity radius since driving
/// covers ground far faster than walking.
enum TourMode {
  driving('Driving Tour', 300, 8000),
  walking('Walking Tour', 60, 1500);

  const TourMode(this.label, this.triggerRadiusMeters, this.stopSearchRadiusMeters);

  final String label;

  /// How close the traveler must get to a stop for it to narrate.
  final double triggerRadiusMeters;

  /// How far from the area to look for candidate stops in the first place —
  /// much wider for driving (miles away is still "in the area" by car) than
  /// walking (has to be realistically walkable).
  final double stopSearchRadiusMeters;
}
