import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';

/// One scored recommendation — [matchedInterests] is what "Recommended
/// because you like X and Y" reads off; empty when the visitor has no
/// interests set (editorial fallback) or the section isn't interest-driven.
class DiscoverRecommendation {
  const DiscoverRecommendation(this.item, this.matchedInterests);
  final DiscoverableItem item;
  final Set<String> matchedInterests;
}

const double _kUnknownDistanceMeters = 1e12; // sorts last, never crashes on null

int _editorialScore(DiscoverableItem i) => (i.featured ? 1000 : 0) + i.priority;

/// Pure, unit-testable recommendation logic (spec: "don't overcomplicate the
/// first implementation" — interests + category + distance + date only; no
/// behavioral learning yet, see `discover_interactions` for that seam).
class DiscoverRecommendationEngine {
  const DiscoverRecommendationEngine();

  /// PICKED FOR YOU — items matching at least one selected interest, ranked
  /// by how many interests matched, then editorial signals, then distance.
  /// Falls back to a pure editorial ranking when [interests] is empty so a
  /// visitor who hasn't picked anything yet still sees something curated
  /// (spec: "users without selected interests still receive useful
  /// recommendations").
  List<DiscoverRecommendation> pickedForYou(
    List<DiscoverableItem> items,
    Set<String> interests, {
    int limit = 10,
  }) {
    if (interests.isEmpty) {
      final sorted = [...items]..sort(_byEditorialThenDistance);
      return sorted.take(limit).map((i) => DiscoverRecommendation(i, const {})).toList();
    }

    final scored = <(DiscoverableItem, Set<String>)>[];
    for (final item in items) {
      final matched = item.interestTags.intersection(interests);
      if (matched.isEmpty) continue;
      scored.add((item, matched));
    }
    scored.sort((a, b) {
      final byCount = b.$2.length.compareTo(a.$2.length);
      if (byCount != 0) return byCount;
      final byEditorial = _editorialScore(b.$1).compareTo(_editorialScore(a.$1));
      if (byEditorial != 0) return byEditorial;
      return _distanceOf(a.$1).compareTo(_distanceOf(b.$1));
    });
    return scored.take(limit).map((e) => DiscoverRecommendation(e.$1, e.$2)).toList();
  }

  /// TODAY — events happening today, nearest-first.
  List<DiscoverableItem> today(List<DiscoverableItem> items, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final todayDate = DateTime(n.year, n.month, n.day);
    final out = items
        .where((i) =>
            i.kind == DiscoverItemKind.event &&
            i.eventDate != null &&
            _sameDate(i.eventDate!, todayDate))
        .toList();
    out.sort(_byDistance);
    return out;
  }

  /// THIS WEEKEND — the next occurring Saturday/Sunday (inclusive of today
  /// if today already is one), nearest-first.
  List<DiscoverableItem> thisWeekend(List<DiscoverableItem> items, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    // DateTime.weekday: Mon=1 ... Sun=7.
    final daysUntilSaturday = (DateTime.saturday - today.weekday) % 7;
    final saturday = today.add(Duration(days: daysUntilSaturday));
    final sunday = saturday.add(const Duration(days: 1));

    final out = items
        .where((i) =>
            i.kind == DiscoverItemKind.event &&
            i.eventDate != null &&
            (_sameDate(i.eventDate!, saturday) || _sameDate(i.eventDate!, sunday)))
        .toList();
    out.sort(_byDistance);
    return out;
  }

  /// NEAR YOU — every item, nearest-first. Works identically whether
  /// [items]' distances were computed from a real GPS fix or a Marion-County
  /// fallback center (the caller decides which; this just sorts).
  List<DiscoverableItem> nearYou(List<DiscoverableItem> items, {int limit = 12}) {
    final out = [...items]..sort(_byDistance);
    return out.take(limit).toList();
  }

  /// YOU MIGHT LIKE — editorial picks the visitor hasn't already been shown,
  /// with a light boost for partial interest overlap when interests exist.
  List<DiscoverableItem> youMightLike(
    List<DiscoverableItem> items,
    Set<String> interests,
    Set<String> alreadyShownIds, {
    int limit = 10,
  }) {
    final candidates = items.where((i) => !alreadyShownIds.contains(i.id)).toList();
    candidates.sort((a, b) {
      final aOverlap = a.interestTags.intersection(interests).length;
      final bOverlap = b.interestTags.intersection(interests).length;
      if (aOverlap != bOverlap) return bOverlap.compareTo(aOverlap);
      final byEditorial = _editorialScore(b).compareTo(_editorialScore(a));
      if (byEditorial != 0) return byEditorial;
      return _distanceOf(a).compareTo(_distanceOf(b));
    });
    return candidates.take(limit).toList();
  }
}

double _distanceOf(DiscoverableItem i) => i.distanceMeters ?? _kUnknownDistanceMeters;
int _byDistance(DiscoverableItem a, DiscoverableItem b) =>
    _distanceOf(a).compareTo(_distanceOf(b));
int _byEditorialThenDistance(DiscoverableItem a, DiscoverableItem b) {
  final byEditorial = _editorialScore(b).compareTo(_editorialScore(a));
  if (byEditorial != 0) return byEditorial;
  return _distanceOf(a).compareTo(_distanceOf(b));
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
