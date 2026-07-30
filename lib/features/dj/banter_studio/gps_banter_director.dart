import 'dart:math';

import 'package:explorer_os_mobile/features/dj/banter_studio/banter_category.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/banter_moment.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/dj_banter_clip.dart';

/// The live travel context the DJ references — GPS plus everything around the
/// visitor right now. Any field may be null; [placeholders] supplies a natural
/// fallback so filled lines always read well.
class GpsBanterContext {
  const GpsBanterContext({
    this.latitude,
    this.longitude,
    this.upcomingAttraction,
    this.park,
    this.county,
    this.road,
    this.nearbyLakes = const [],
    this.nearbyRivers = const [],
    this.nearbySprings = const [],
    this.nearbyTrails = const [],
    this.nearbyHistoricSites = const [],
    this.nearbyWildlife = const [],
    this.guideMode,
    this.songTitle,
    this.artist,
    this.storyTitle,
    this.station = 'Explorer Radio',
    this.dj,
    this.destinationCode,
    this.moment,
  });

  final double? latitude;
  final double? longitude;
  final String? upcomingAttraction;
  final String? park;
  final String? county;
  final String? road;
  final List<String> nearbyLakes;
  final List<String> nearbyRivers;
  final List<String> nearbySprings;
  final List<String> nearbyTrails;
  final List<String> nearbyHistoricSites;
  final List<String> nearbyWildlife;
  final String? guideMode;
  final String? songTitle;
  final String? artist;
  final String? storyTitle;
  final String station;
  final String? dj;
  final String? destinationCode;

  /// The live time-of-day / season / weather. When set, clips tagged for a
  /// dimension only play when the moment matches (untagged = universal).
  final BanterMoment? moment;

  static String _first(List<String> xs, String fallback) =>
      xs.isEmpty ? fallback : xs.first;

  /// Placeholder → value map used to fill a clip's `{tokens}`.
  Map<String, String> placeholders() => {
        'station': station,
        'dj': dj ?? 'your host',
        'park': park ?? 'this area',
        'county': county ?? 'the county',
        'road': road ?? 'this road',
        'attraction': upcomingAttraction ?? 'the road ahead',
        'upcoming_attraction': upcomingAttraction ?? 'the road ahead',
        'guide_mode': guideMode ?? 'explorer',
        'song_title': songTitle ?? 'that track',
        'artist': artist ?? 'a local artist',
        'story': storyTitle ?? 'a story worth hearing',
        'nearby_lake': _first(nearbyLakes, 'a nearby lake'),
        'nearby_river': _first(nearbyRivers, 'a nearby river'),
        'nearby_spring': _first(nearbySprings, 'a nearby spring'),
        'nearby_trail': _first(nearbyTrails, 'a nearby trail'),
        'nearby_historic_site': _first(nearbyHistoricSites, 'a historic site'),
        'nearby_wildlife': _first(nearbyWildlife, 'local wildlife'),
      };
}

/// The result of a selection: the chosen clip, its filled conversational line,
/// and what it naturally transitions into.
class BanterSelection {
  const BanterSelection({
    required this.clip,
    required this.text,
    required this.transition,
  });

  final DjBanterClip clip;
  final String text;
  final BanterTransition transition;
}

/// Per-trip rotation memory. Tracks the four signals the brief calls out —
/// `last_played`, `play_count`, `trip_played`, `destination_played` — plus a
/// short recent window used for the cooldown ("hasn't been played recently").
class BanterTrip {
  BanterTrip({this.recentWindow = 6});

  final int recentWindow;

  /// Clip ids already aired this trip (never repeat within a trip).
  final Set<String> tripPlayed = {};

  /// Lifetime play counts per clip id (`play_count`).
  final Map<String, int> playCount = {};

  /// Last time each clip aired (`last_played`).
  final Map<String, DateTime> lastPlayed = {};

  /// Plays per destination code (`destination_played`).
  final Map<String, int> destinationPlayed = {};

  /// Most-recent-first ring of clip ids for the cooldown.
  final List<String> recent = [];

  int tripCount = 0;

  bool playedThisTrip(String id) => tripPlayed.contains(id);

  int destinationPlays(String? code) =>
      code == null ? 0 : (destinationPlayed[code] ?? 0);

  bool recentlyPlayed(String id) => recent.contains(id);

  void markPlayed(DjBanterClip clip, {DateTime? now}) {
    tripPlayed.add(clip.id);
    playCount[clip.id] = (playCount[clip.id] ?? 0) + 1;
    lastPlayed[clip.id] = now ?? DateTime.now();
    final code = clip.destinationCode;
    if (code != null && code.isNotEmpty) {
      destinationPlayed[code] = (destinationPlayed[code] ?? 0) + 1;
    }
    recent.insert(0, clip.id);
    while (recent.length > recentWindow) {
      recent.removeLast();
    }
  }

  /// Begins a new trip: clears trip-played so the library can play again, in a
  /// fresh order. Lifetime counts and the recent window are preserved.
  void startNewTrip() {
    tripPlayed.clear();
    tripCount++;
  }
}

/// Fills a clip's `{placeholders}` from context and tidies whitespace.
String fillBanter(String template, GpsBanterContext ctx) {
  final map = ctx.placeholders();
  final out = template.replaceAllMapped(
    RegExp(r'\{(\w+)\}'),
    (m) => map[m.group(1)] ?? '',
  );
  return out.replaceAll(RegExp(r'\s+'), ' ').replaceAll(' .', '.').trim();
}

/// GPS-Aware DJ Banter Director.
///
/// Given a destination's banter library, the live GPS context, and the trip's
/// rotation memory, it selects a clip for a category (or the first category with
/// something to say from a priority list), respecting cooldown and never
/// repeating the same banter during a trip, then fills its GPS placeholders into
/// a conversational line. Pure + deterministic under an injected [Random].
class GpsBanterDirector {
  GpsBanterDirector({Random? random}) : _rng = random ?? Random();

  final Random _rng;

  /// Clips eligible right now for [category]: published, matching the current
  /// destination (or clip has no destination / matches GPS region), fitting the
  /// guide mode, not already played this trip, and not in the recent cooldown.
  List<DjBanterClip> eligible(
    List<DjBanterClip> library,
    BanterCategory category,
    GpsBanterContext ctx,
    BanterTrip trip, {
    bool ignoreCooldown = false,
  }) {
    return library.where((c) {
      if (c.category != category) return false;
      if (!c.isPublished) return false;
      if ((c.text).trim().isEmpty && !c.hasAudio) return false;
      if (!_matchesLocation(c, ctx)) return false;
      if (!_matchesGuide(c, ctx)) return false;
      if (ctx.moment != null && !clipMatchesMoment(c.tags, ctx.moment!)) {
        return false;
      }
      if (trip.playedThisTrip(c.id)) return false;
      if (!ignoreCooldown && trip.recentlyPlayed(c.id)) return false;
      return true;
    }).toList();
  }

  /// Picks (and marks played) a clip for [category], or null if nothing fits.
  ///
  /// If every clip in the category has already aired this trip, the trip resets
  /// so the library can play again in a fresh order (never dead air).
  BanterSelection? pick(
    List<DjBanterClip> library,
    BanterCategory category,
    GpsBanterContext ctx,
    BanterTrip trip, {
    DateTime? now,
    bool mark = true,
  }) {
    var pool = eligible(library, category, ctx, trip);
    if (pool.isEmpty) {
      // Nothing fresh — allow recently-played (still not repeat-in-trip).
      pool = eligible(library, category, ctx, trip, ignoreCooldown: true);
    }
    if (pool.isEmpty) {
      // Whole category exhausted this trip → new trip, try once more.
      final anyInCategory = library.any((c) =>
          c.category == category &&
          c.isPublished &&
          _matchesLocation(c, ctx) &&
          _matchesGuide(c, ctx));
      if (!anyInCategory) return null;
      trip.startNewTrip();
      pool = eligible(library, category, ctx, trip, ignoreCooldown: true);
    }
    if (pool.isEmpty) return null;

    // Prefer the least-played clips, then choose randomly among them so order
    // never repeats and favorites don't dominate.
    pool.sort((a, b) {
      final ap = trip.playCount[a.id] ?? 0;
      final bp = trip.playCount[b.id] ?? 0;
      return ap.compareTo(bp);
    });
    final minPlays = trip.playCount[pool.first.id] ?? 0;
    final leastPlayed =
        pool.where((c) => (trip.playCount[c.id] ?? 0) == minPlays).toList();
    final clip = leastPlayed[_rng.nextInt(leastPlayed.length)];

    if (mark) trip.markPlayed(clip, now: now);
    return BanterSelection(
      clip: clip,
      text: fillBanter(clip.text, ctx),
      transition: clip.category.transition,
    );
  }

  /// Picks the first category (in [priority] order) that has something to say.
  /// Handy for "the DJ should say something now — what's most relevant?".
  BanterSelection? pickAny(
    List<DjBanterClip> library,
    List<BanterCategory> priority,
    GpsBanterContext ctx,
    BanterTrip trip, {
    DateTime? now,
  }) {
    for (final category in priority) {
      final sel = pick(library, category, ctx, trip, now: now);
      if (sel != null) return sel;
    }
    return null;
  }

  bool _matchesLocation(DjBanterClip c, GpsBanterContext ctx) {
    // No targeting → usable anywhere.
    final hasDest = (c.destinationCode ?? '').trim().isNotEmpty;
    final hasRegion = (c.gpsRegion ?? '').trim().isNotEmpty;
    if (!hasDest && !hasRegion) return true;
    if (hasDest &&
        ctx.destinationCode != null &&
        c.destinationCode!.toLowerCase() == ctx.destinationCode!.toLowerCase()) {
      return true;
    }
    if (hasRegion && ctx.park != null &&
        (ctx.park!.toLowerCase().contains(c.gpsRegion!.toLowerCase()) ||
            c.gpsRegion!.toLowerCase().contains(ctx.park!.toLowerCase()))) {
      return true;
    }
    // Targeted clip but context doesn't match → not eligible, unless the
    // context has no destination at all (fall back to letting it play).
    return ctx.destinationCode == null && ctx.park == null;
  }

  bool _matchesGuide(DjBanterClip c, GpsBanterContext ctx) {
    final g = (c.guideMode ?? '').trim();
    if (g.isEmpty) return true; // fits any guide mode
    if (ctx.guideMode == null) return true;
    return g.toLowerCase() == ctx.guideMode!.toLowerCase();
  }
}
