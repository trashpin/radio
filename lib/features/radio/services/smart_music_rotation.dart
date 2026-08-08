/// Smart Music Rotation Engine.
///
/// Replaces sequential ("play the next song in the list") playback with a
/// scored, anti-repeat rotation so the station sounds different every drive:
///
///   • Never plays songs in the same order twice (weighted random over the top
///     scorers + a per-trip random seed).
///   • Never repeats a song during the same trip (a song is excluded once it
///     has aired until the trip resets).
///   • Scores every song by park, nearby attraction, guide mode, time of day,
///     season, weather (future), tags, mood, tempo, duration, popularity, and a
///     random seed.
///   • Temporarily reduces a song's score right after it plays (a decaying
///     "recently played" cooldown) so a different song is chosen next.
///
/// The engine is pure and deterministic given an injected [Random], which makes
/// it fully unit-testable; production uses an unseeded [Random] per trip so
/// every drive is unique even with the same music library.
library;

import 'dart:math';

/// A song's rough energy level, used for time-of-day weighting.
enum MusicTempo { slow, medium, fast }

/// Coarse time-of-day bucket used for tempo weighting.
enum MusicDaypart {
  morning,
  afternoon,
  evening,
  night;

  static MusicDaypart fromHour(int hour) {
    if (hour < 12) return MusicDaypart.morning;
    if (hour < 17) return MusicDaypart.afternoon;
    if (hour < 21) return MusicDaypart.evening;
    return MusicDaypart.night;
  }

  static MusicDaypart now([DateTime? clock]) =>
      fromHour((clock ?? DateTime.now()).hour);
}

/// Meteorological season used for seasonal tag weighting.
enum MusicSeason {
  spring,
  summer,
  fall,
  winter;

  static MusicSeason fromMonth(int month) {
    if (month >= 3 && month <= 5) return MusicSeason.spring;
    if (month >= 6 && month <= 8) return MusicSeason.summer;
    if (month >= 9 && month <= 11) return MusicSeason.fall;
    return MusicSeason.winter;
  }

  static MusicSeason now([DateTime? clock]) =>
      fromMonth((clock ?? DateTime.now()).month);
}

/// Preferred energy for a daypart (mornings ease in, afternoons drive, nights
/// wind down).
MusicTempo tempoForDaypart(MusicDaypart daypart) {
  switch (daypart) {
    case MusicDaypart.morning:
      return MusicTempo.medium;
    case MusicDaypart.afternoon:
      return MusicTempo.fast;
    case MusicDaypart.evening:
      return MusicTempo.medium;
    case MusicDaypart.night:
      return MusicTempo.slow;
  }
}

String _norm(String s) => s.trim().toLowerCase();
bool _eq(String? a, String? b) =>
    a != null && b != null && _norm(a) == _norm(b);

/// A single candidate track. Metadata is optional — the engine degrades
/// gracefully (missing dimensions simply don't contribute to the score).
class RotationSong {
  const RotationSong({
    required this.id,
    required this.audioUrl,
    this.title = '',
    this.park,
    this.tags = const [],
    this.mood,
    this.tempo,
    this.durationSeconds,
    this.popularity,
  });

  final String id;
  final String audioUrl;
  final String title;

  /// Park/destination this song is associated with (matched against context).
  final String? park;

  /// Free-form tags (genre, station, mood words, season names, attraction
  /// categories) — matched against the context's nearby categories and season.
  final List<String> tags;

  /// Optional mood word (matched against guide mode / preferred mood).
  final String? mood;
  final MusicTempo? tempo;
  final int? durationSeconds;

  /// Optional popularity in 0..1.
  final double? popularity;
}

/// Everything known about the moment a song is being chosen.
class RotationContext {
  const RotationContext({
    this.park,
    this.nearbyCategories = const [],
    this.countyCategories = const [],
    this.guideMode,
    this.daypart,
    this.season,
    this.preferredMood,
    this.preferredTempo,
  });

  final String? park;
  final List<String> nearbyCategories;

  /// The current county's preferred music genres/categories
  /// (`CountyConfig.musicCategories`, e.g. country/americana/southern for
  /// Marion). Songs whose tags overlap these get a county-match bonus.
  final List<String> countyCategories;
  final String? guideMode;
  final MusicDaypart? daypart;
  final MusicSeason? season;
  final String? preferredMood;
  final MusicTempo? preferredTempo;

  /// Builds a context from the current clock (time of day + season).
  factory RotationContext.now({
    String? park,
    List<String> nearbyCategories = const [],
    List<String> countyCategories = const [],
    String? guideMode,
    String? preferredMood,
    MusicTempo? preferredTempo,
    DateTime? clock,
  }) {
    final t = clock ?? DateTime.now();
    return RotationContext(
      park: park,
      nearbyCategories: nearbyCategories,
      countyCategories: countyCategories,
      guideMode: guideMode,
      preferredMood: preferredMood,
      preferredTempo: preferredTempo,
      daypart: MusicDaypart.now(t),
      season: MusicSeason.now(t),
    );
  }
}

/// Tunable score weights (kept in one place so behavior is easy to reason about
/// and test).
class RotationWeights {
  const RotationWeights({
    this.park = 20,
    this.nearby = 6,
    this.nearbyCap = 12,
    this.county = 5,
    this.countyCap = 10,
    this.guide = 10,
    this.timeOfDay = 8,
    this.season = 6,
    this.mood = 8,
    this.durationFit = 4,
    this.popularity = 8,
    this.random = 15,
    this.recentPenalty = 45,
    this.overplay = 1.5,
    this.parkRepeat = 2.0,
  });

  final double park;
  final double nearby;
  final double nearbyCap;

  /// Per-overlapping-tag bonus (and cap) when a song's tags match the current
  /// county's music categories.
  final double county;
  final double countyCap;
  final double guide;
  final double timeOfDay;
  final double season;
  final double mood;
  final double durationFit;
  final double popularity;

  /// Max additive jitter (the random seed) that keeps order fresh each trip.
  final double random;

  /// Full penalty applied to the most-recently-played song (decays across the
  /// recent window).
  final double recentPenalty;

  /// Per-lifetime-play penalty (discourages overplaying favorites).
  final double overplay;

  /// Per-play-in-this-park penalty (spreads plays across the library).
  final double parkRepeat;

  static const defaults = RotationWeights();
}

/// Mutable rotation memory. Tracks the four required signals — `last_played`,
/// `play_count`, `trip_played`, `park_played` — plus a short recent-window used
/// for the temporary post-play score reduction.
class RotationTracker {
  RotationTracker({this.recentWindow = 3});

  final int recentWindow;

  /// Songs already aired this trip (never repeat within a trip).
  final Set<String> tripPlayed = {};

  /// Lifetime play counts per song id (`play_count`).
  final Map<String, int> playCount = {};

  /// Last time each song aired (`last_played`).
  final Map<String, DateTime> lastPlayed = {};

  /// Plays per `park::id` (`park_played`).
  final Map<String, int> _parkPlayed = {};

  /// Most-recent-first ring of song ids, sized to [recentWindow].
  final List<String> recent = [];

  /// How many trips have started (a new drive = a fresh seed + no repeats).
  int tripCount = 0;

  int parkPlayCount(String park, String id) => _parkPlayed['$park::$id'] ?? 0;

  bool playedThisTrip(String id) => tripPlayed.contains(id);

  void markPlayed(String id, {String? park, DateTime? now}) {
    tripPlayed.add(id);
    playCount[id] = (playCount[id] ?? 0) + 1;
    lastPlayed[id] = now ?? DateTime.now();
    if (park != null && park.trim().isNotEmpty) {
      final k = '$park::$id';
      _parkPlayed[k] = (_parkPlayed[k] ?? 0) + 1;
    }
    recent.insert(0, id);
    while (recent.length > recentWindow) {
      recent.removeLast();
    }
  }

  /// Resets per-trip state so the library can play again in a fresh order. The
  /// recent window is preserved so we don't immediately repeat across the seam.
  void startNewTrip() {
    tripPlayed.clear();
    tripCount++;
  }
}

/// A song paired with its computed score (exposed for telemetry/tests).
class ScoredSong {
  const ScoredSong(this.song, this.score);
  final RotationSong song;
  final double score;
}

/// The engine. Owns a [RotationTracker] and a [Random]; one engine instance
/// represents one continuous listening session ("trip").
class SmartMusicRotationEngine {
  SmartMusicRotationEngine({
    Random? random,
    RotationTracker? tracker,
    this.weights = RotationWeights.defaults,
    this.topK = 5,
    int recentWindow = 3,
  })  : _rng = random ?? Random(),
        tracker = tracker ?? RotationTracker(recentWindow: recentWindow);

  final Random _rng;
  final RotationTracker tracker;
  final RotationWeights weights;

  /// How many of the top-scoring songs to draw the weighted pick from.
  final int topK;

  /// Scores one song for the given moment. [jitter] is the random-seed
  /// contribution (0..weights.random); pass 0 for a deterministic score.
  double scoreSong(
    RotationSong song,
    RotationContext ctx, {
    double jitter = 0,
  }) {
    var s = 50.0;

    // Current park.
    if (_eq(song.park, ctx.park)) s += weights.park;

    // Nearby attraction — tag overlap with the surrounding categories.
    if (ctx.nearbyCategories.isNotEmpty && song.tags.isNotEmpty) {
      final overlap = song.tags
          .where((t) => ctx.nearbyCategories.any((n) => _eq(n, t)))
          .length;
      if (overlap > 0) {
        s += min(overlap * weights.nearby, weights.nearbyCap);
      }
    }

    // County music categories — favor songs tagged with the current county's
    // genres (e.g. Marion → country/americana/southern). Additive; contributes
    // nothing when the county has no configured categories.
    if (ctx.countyCategories.isNotEmpty && song.tags.isNotEmpty) {
      final overlap = song.tags
          .where((t) => ctx.countyCategories.any((c) => _eq(c, t)))
          .length;
      if (overlap > 0) {
        s += min(overlap * weights.county, weights.countyCap);
      }
    }

    // Guide mode (treated as a mood preference).
    if (_eq(song.mood, ctx.guideMode)) s += weights.guide;

    // Explicit preferred mood.
    if (_eq(song.mood, ctx.preferredMood)) s += weights.mood;

    // Time of day → preferred tempo.
    final prefTempo = ctx.preferredTempo ??
        (ctx.daypart != null ? tempoForDaypart(ctx.daypart!) : null);
    if (prefTempo != null && song.tempo == prefTempo) s += weights.timeOfDay;

    // Season — a tag naming the current season.
    if (ctx.season != null &&
        song.tags.any((t) => _eq(t, ctx.season!.name))) {
      s += weights.season;
    }

    // Duration fit — favor a comfortable 90s..7min track.
    final d = song.durationSeconds;
    if (d != null && d > 0) {
      s += (d >= 90 && d <= 420) ? weights.durationFit : -weights.durationFit;
    }

    // Popularity.
    final pop = song.popularity;
    if (pop != null) s += pop.clamp(0.0, 1.0) * weights.popularity;

    // Weather: reserved for the future — contributes nothing today.

    // Random seed — the variety engine.
    s += jitter;

    // --- Temporary + long-term reductions --------------------------------
    // Recently played cooldown (decays as it slides out of the window).
    final ri = tracker.recent.indexOf(song.id);
    if (ri >= 0) {
      final w = tracker.recentWindow == 0 ? 1 : tracker.recentWindow;
      s -= weights.recentPenalty * ((w - ri) / w);
    }
    // Overplay penalties.
    s -= (tracker.playCount[song.id] ?? 0) * weights.overplay;
    if (ctx.park != null) {
      s -= tracker.parkPlayCount(ctx.park!, song.id) * weights.parkRepeat;
    }
    return s;
  }

  /// Scores every candidate (excluding songs already aired this trip) using the
  /// engine's RNG for jitter, sorted best-first. Does not mutate the tracker.
  List<ScoredSong> scoredCandidates(
    List<RotationSong> songs,
    RotationContext ctx,
  ) {
    final pool = _tripPool(songs);
    final scored = [
      for (final song in pool)
        ScoredSong(song, scoreSong(song, ctx, jitter: _jitter())),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  /// Chooses the next song: score the trip's remaining candidates, take the
  /// top-[topK], and pick one weighted by score (so it's never strictly
  /// sequential and never the same order twice). Marks it played by default.
  RotationSong? pickNext(
    List<RotationSong> songs,
    RotationContext ctx, {
    DateTime? now,
    bool mark = true,
  }) {
    if (songs.isEmpty) return null;
    final scored = scoredCandidates(songs, ctx);
    if (scored.isEmpty) return null;

    final k = min(topK, scored.length);
    final top = scored.sublist(0, k);
    final picked = _weightedPick(top);
    if (mark) {
      tracker.markPlayed(picked.id, park: ctx.park, now: now ?? DateTime.now());
    }
    return picked;
  }

  /// Ends the current trip and starts a fresh one (call at the start of every
  /// drive so ordering resets and no in-trip repeats carry over).
  void startNewTrip() => tracker.startNewTrip();

  // --- internals ------------------------------------------------------------

  double _jitter() => _rng.nextDouble() * weights.random;

  List<RotationSong> _tripPool(List<RotationSong> songs) {
    final pool = songs.where((s) => !tracker.playedThisTrip(s.id)).toList();
    if (pool.isNotEmpty) return pool;
    // Whole library exhausted this trip → reset and reuse everything.
    tracker.startNewTrip();
    return List.of(songs);
  }

  RotationSong _weightedPick(List<ScoredSong> top) {
    if (top.length == 1) return top.first.song;
    // Shift so the lowest score maps to a small positive weight, preserving the
    // relative ranking while keeping every top candidate reachable.
    final minScore = top.map((e) => e.score).reduce(min);
    final shift = minScore <= 0 ? (1 - minScore) : 0.0;
    var total = 0.0;
    for (final e in top) {
      total += e.score + shift;
    }
    if (total <= 0) return top[_rng.nextInt(top.length)].song;
    var roll = _rng.nextDouble() * total;
    for (final e in top) {
      roll -= e.score + shift;
      if (roll <= 0) return e.song;
    }
    return top.last.song;
  }
}
