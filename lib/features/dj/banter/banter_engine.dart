import 'dart:math';

/// The station a DJ / template belongs to. `all` = usable by any station.
enum DjStation {
  all('All stations'),
  country('Country'),
  rock('Rock'),
  topHits('Top Hits'),
  kids('Kids');

  const DjStation(this.label);
  final String label;
}

/// The moment in the broadcast a piece of banter is for.
enum BanterSituation {
  openingShow('Opening show'),
  songIntro('Song intro'),
  songOutro('Song outro'),
  gpsApproaching('GPS approaching'),
  wildlifeSighting('Wildlife sighting'),
  safetyReminder('Safety reminder'),
  weather('Weather'),
  campground('Campground'),
  trail('Trail'),
  sunset('Sunset'),
  sunrise('Sunrise'),
  stationId('Station ID');

  const BanterSituation(this.label);
  final String label;
}

/// The live context a template is filled from. Any field may be null; the engine
/// substitutes a natural fallback so output always reads well.
class BanterContext {
  const BanterContext({
    this.station = 'Ocala National Forest Radio',
    this.park = 'Ocala National Forest',
    this.songTitle,
    this.artist,
    this.landmark,
    this.timeOfDay,
    this.weather,
    this.wildlife,
    this.mood,
    this.theme,
    this.djName,
    this.story,
  });

  final String station;
  final String park;
  final String? songTitle;
  final String? artist;
  final String? landmark;
  final String? timeOfDay;
  final String? weather;
  final String? wildlife;
  final String? mood;
  final String? theme;
  final String? djName;
  final String? story;

  Map<String, String> placeholders() => {
        'station': station,
        'park': park,
        'song_title': songTitle ?? 'that track',
        'artist': artist ?? 'a local artist',
        'landmark': landmark ?? 'the road ahead',
        'time_of_day': timeOfDay ?? 'today',
        'weather': weather ?? 'beautiful weather',
        'wildlife': wildlife ?? 'local wildlife',
        'mood': mood ?? 'easygoing',
        'theme': theme ?? "Florida's wild places",
        'dj': djName ?? 'your host',
        'story': story ?? 'a story worth hearing',
      };
}

/// A single banter template: a line of DJ script with `{placeholders}`.
class BanterTemplate {
  const BanterTemplate(this.station, this.situation, this.text);
  final DjStation station;
  final BanterSituation situation;
  final String text;
}

/// Turns templates + live context into DJ banter, with random rotation so the
/// same situation (or song) rarely sounds the same twice.
///
/// PURE + deterministic when seeded — no I/O, no AI at runtime. AI is only used
/// at authoring time to add new templates; playback just fills + rotates these.
class BanterEngine {
  BanterEngine({List<BanterTemplate>? templates, Random? rng})
      : templates = templates ?? kBanterTemplates,
        _rng = rng ?? Random();

  final List<BanterTemplate> templates;
  final Random _rng;

  /// Templates matching a station+situation (station-specific first, then the
  /// `all` pool).
  List<BanterTemplate> templatesFor(DjStation station, BanterSituation s) {
    final specific =
        templates.where((t) => t.situation == s && t.station == station);
    final shared =
        templates.where((t) => t.situation == s && t.station == DjStation.all);
    return [...specific, ...shared];
  }

  /// Fills a template string with the context (unknown placeholders → empty,
  /// then whitespace is tidied).
  static String fill(String template, BanterContext ctx) {
    final map = ctx.placeholders();
    final out = template.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (m) => map[m.group(1)] ?? '',
    );
    return out.replaceAll(RegExp(r'\s+'), ' ').replaceAll(' .', '.').trim();
  }

  /// Generates one banter line for the given station+situation, or null if no
  /// template exists.
  String? generate(
    DjStation station,
    BanterSituation situation,
    BanterContext ctx,
  ) {
    final pool = templatesFor(station, situation);
    if (pool.isEmpty) return null;
    return fill(pool[_rng.nextInt(pool.length)].text, ctx);
  }

  /// A song intro built from the song-intro pool (a common convenience).
  String? songIntro(DjStation station, BanterContext ctx) =>
      generate(station, BanterSituation.songIntro, ctx);
}

/// Seed template library. 10-20 total per situation across stations gives lots
/// of rotation; more can be added in the DJ Studio. `all` templates apply to
/// every station.
const List<BanterTemplate> kBanterTemplates = [
  // ── Opening show ──
  BanterTemplate(DjStation.all, BanterSituation.openingShow,
      'Good {time_of_day}, explorers! You\'re tuned to {station}, where every mile has a story.'),
  BanterTemplate(DjStation.all, BanterSituation.openingShow,
      'Welcome back to {station}. Roll down the windows — we\'ve got music and stories from {park} all {time_of_day} long.'),
  BanterTemplate(DjStation.country, BanterSituation.openingShow,
      'Howdy, y\'all — this is {station}. Grab the wheel and settle in for some country inspired by {theme}.'),
  BanterTemplate(DjStation.kids, BanterSituation.openingShow,
      'Hi explorers! It\'s time for fun on {station}. Are you ready to sing along as we roll through {park}?'),

  // ── Song intro ──
  BanterTemplate(DjStation.all, BanterSituation.songIntro,
      'Up next on {station}, here\'s "{song_title}" — a tune inspired by {theme}.'),
  BanterTemplate(DjStation.all, BanterSituation.songIntro,
      'Coming up, "{song_title}" by {artist}. If you\'re near {landmark}, this one\'s for you.'),
  BanterTemplate(DjStation.country, BanterSituation.songIntro,
      'Here\'s a country tune inspired by the winding roads and towering longleaf pines of {park} — "{song_title}".'),
  BanterTemplate(DjStation.rock, BanterSituation.songIntro,
      'Time to turn it up! Here\'s a rock anthem inspired by Florida\'s back roads and hidden springs — "{song_title}".'),
  BanterTemplate(DjStation.topHits, BanterSituation.songIntro,
      'You\'re listening to {station}. Here\'s a fresh one climbing the charts — "{song_title}" by {artist}.'),
  BanterTemplate(DjStation.kids, BanterSituation.songIntro,
      'Here comes a fun one! Let\'s clap along to "{song_title}" as we explore {park}.'),

  // ── Song outro ──
  BanterTemplate(DjStation.all, BanterSituation.songOutro,
      'That was "{song_title}". If you\'re driving near {landmark}, keep an eye out for {wildlife}, especially around sunrise and sunset.'),
  BanterTemplate(DjStation.all, BanterSituation.songOutro,
      'That was "{song_title}" by {artist} — more music from {park} coming right up on {station}.'),
  BanterTemplate(DjStation.all, BanterSituation.songOutro,
      'Thanks for riding along with us. Keep your eyes open — this stretch is one of the best places to spot {wildlife}.'),

  // ── GPS approaching (a story is near) ──
  BanterTemplate(DjStation.all, BanterSituation.gpsApproaching,
      'Coming up in just a moment, we\'ll tell you the story behind {landmark}. First, here\'s another song inspired by {theme}.'),
  BanterTemplate(DjStation.all, BanterSituation.gpsApproaching,
      'You\'re getting close to {landmark} — stay with us, {story} is right after this song on {station}.'),

  // ── Wildlife sighting / transition ──
  BanterTemplate(DjStation.all, BanterSituation.wildlifeSighting,
      'Looks like you\'re entering {wildlife} habitat. Don\'t worry — we\'ll tell you what to watch for after this next song.'),
  BanterTemplate(DjStation.all, BanterSituation.wildlifeSighting,
      'Keep those eyes peeled near {landmark}: this is prime {wildlife} territory this time of year.'),

  // ── Safety reminder ──
  BanterTemplate(DjStation.all, BanterSituation.safetyReminder,
      'Quick reminder from {station}: keep your distance from wildlife and pack out what you pack in. Now, back to the music.'),
  BanterTemplate(DjStation.all, BanterSituation.safetyReminder,
      'Safety first, explorers — {weather} out there, so stay hydrated and watch the road through {park}.'),

  // ── Weather ──
  BanterTemplate(DjStation.all, BanterSituation.weather,
      'It\'s {weather} across {park} this {time_of_day} — a perfect day to explore. Here\'s more music on {station}.'),

  // ── Campground ──
  BanterTemplate(DjStation.all, BanterSituation.campground,
      'If you\'re settling in near {landmark} tonight, {station} makes the perfect campfire soundtrack.'),

  // ── Trail ──
  BanterTemplate(DjStation.all, BanterSituation.trail,
      'Lacing up for {landmark}? Take {station} along — every step through {park} has a story.'),

  // ── Sunset / Sunrise ──
  BanterTemplate(DjStation.all, BanterSituation.sunset,
      'The sun\'s going down over {park} — golden hour on {station}. Watch for {wildlife} coming out to feed.'),
  BanterTemplate(DjStation.all, BanterSituation.sunrise,
      'Good morning from {park}! Sunrise is the best time to spot {wildlife} — here\'s a fresh track on {station}.'),

  // ── Station ID ──
  BanterTemplate(DjStation.all, BanterSituation.stationId,
      'You\'re listening to {station} — music, stories, and discovery from {park}.'),
];
