/// Guards mission-stop arrival against a single noisy or drifted GPS fix
/// momentarily reporting "inside" a stop's arrival radius. A stop is only
/// confirmed arrived once [requiredStreak] consecutive fixes in a row all
/// land inside the radius — one stray fix, or a car merely passing near the
/// destination without stopping, must not be enough on its own (spec: "a
/// mission stop should not be considered completed simply because the user
/// briefly enters the geofence").
///
/// Mirrors the same "consecutive streak" idiom [TripTracker] already uses
/// for its own off-route detection — reused for a second kind of geofence
/// event, not a new debouncing approach invented for this feature.
class ArrivalConfirmer {
  ArrivalConfirmer({this.requiredStreak = 2});
  final int requiredStreak;
  final Map<String, int> _streaks = {};

  /// Returns true once [stopId] has now been reported inside its arrival
  /// radius for [requiredStreak] consecutive calls in a row. Any call with
  /// [isInsideRadius] false resets that stop's streak back to zero — the
  /// player must be continuously inside, not just inside on average.
  bool confirm(String stopId, bool isInsideRadius) {
    if (!isInsideRadius) {
      _streaks.remove(stopId);
      return false;
    }
    final next = (_streaks[stopId] ?? 0) + 1;
    _streaks[stopId] = next;
    return next >= requiredStreak;
  }
}
