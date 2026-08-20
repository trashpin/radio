import 'package:explorer_os_mobile/core/utils/greeting.dart';
import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';

/// MARION COUNTY EXPLORE's fixed programming order (spec section 5). Content
/// for each category is sourced from existing tables (see
/// `explore_providers.dart`) — this enum only orders the rotation.
enum ExploreCategory {
  whereHeaded,
  whereYouAre,
  events,
  county,
  wildlife,
  nature,
  geology,
  history,
  teaser;

  String get label {
    switch (this) {
      case ExploreCategory.whereHeaded:
        return "Where You're Headed";
      case ExploreCategory.whereYouAre:
        return 'Where You Are';
      case ExploreCategory.events:
        return 'Events';
      case ExploreCategory.county:
        return 'Marion County';
      case ExploreCategory.wildlife:
        return 'Animals & Wildlife';
      case ExploreCategory.nature:
        return 'Nature';
      case ExploreCategory.geology:
        return 'Geology';
      case ExploreCategory.history:
        return 'History';
      case ExploreCategory.teaser:
        return 'Coming Up';
    }
  }
}

/// One piece of existing content, normalized for the Explore rotation —
/// mirrors [DiscoveryCandidate]'s shape so both schedulers stay consistent,
/// but keeps its own type since Explore candidates carry a
/// [TellMeMoreContext] (so a played segment can open the existing TELL ME
/// MORE screen) and aren't distance-gated the way background discovery is.
class ExploreCandidate {
  const ExploreCandidate({
    required this.id,
    required this.category,
    required this.title,
    this.audioUrl,
    this.spokenText,
    this.tellMeMoreContext,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.distanceMeters,
    this.eta,
    this.aheadPriority = 1000,
    this.sessionKey,
    this.isAheadOfTravel = true,
  });

  final String id;
  final ExploreCategory category;
  final String title;
  final String? audioUrl;
  final String? spokenText;
  final TellMeMoreContext? tellMeMoreContext;

  /// Type-based priority among simultaneously-qualifying "what's ahead"
  /// candidates (lower wins) — e.g. a State Park outranks a Town even when
  /// the Town is nearer. Only meaningful for [ExploreCategory.whereHeaded]/
  /// [ExploreCategory.events]/[ExploreCategory.teaser] candidates; the
  /// default (1000) means "not applicable" for every other category.
  final int aheadPriority;

  /// The photo for whatever this candidate is about — carried on the
  /// resulting [AudioSegment] itself (not resolved separately later) so the
  /// image, name, narration, and NAVIGATE target can never drift apart
  /// (spec section 11: "current subject").
  final String? imageUrl;

  /// NAVIGATE target — present only when this candidate is genuinely tied to
  /// a physical destination (a location/event/park's own coordinates, never
  /// invented). Null for county-wide or non-geo content, which correctly
  /// shows no NAVIGATE button (spec section 7).
  final double? latitude;
  final double? longitude;

  /// Distance/ETA from the traveler, when this candidate came from the
  /// ahead-of-travel search — carried on the candidate itself (not
  /// recomputed separately) so the "close enough to interrupt for" check
  /// always agrees with what's actually being narrated.
  final double? distanceMeters;
  final Duration? eta;

  /// Which physical destination this candidate is ABOUT, for cross-category
  /// "related content" lookup inside a travel-companion session (spec: "For
  /// an added bit of Florida wildlife, keep an eye out for..." — a MEANINGFUL
  /// connection, not a random pick). Set by the provider layer using the same
  /// stable id scheme `_aheadCandidates` already uses for its own candidates
  /// (`'loc:<id>'`/`'evt:<id>'`); null means "not tied to a specific place"
  /// (the species/county pools, mostly), which simply can't be found by a
  /// session — never forced.
  final String? sessionKey;

  /// True for a candidate genuinely detected ahead of travel (built by
  /// `_aheadCandidates`'s cone+radius+ETA search — the ONLY function that
  /// ever builds `whereHeaded`/`teaser` category candidates, so it's always
  /// true for those). `events` is the one category with mixed provenance —
  /// both an ahead-of-travel event AND a merely-nearby, non-directional one
  /// (`_nearbyEventCandidates`) share the `events` category, so THAT source
  /// explicitly sets this false. [_pickAheadAcross] (the REVEAL step) filters
  /// on this flag so a plain nearby event can still fill the INFORMATION
  /// fallback tier via [_pick], but never masquerades as an ahead-of-travel
  /// reveal worth building a full travel-companion session around.
  final bool isAheadOfTravel;

  bool get isPlayable =>
      (audioUrl ?? '').trim().isNotEmpty || (spokenText ?? '').trim().isNotEmpty;
  bool get hasDestination => latitude != null && longitude != null;
}

/// A candidate that has become urgent enough to jump the rotation (spec
/// section 7 — "Coming up ahead is Silver Springs…"). Playing one does NOT
/// advance or reset the normal rotation cursor.
class ExploreUrgentCandidate {
  const ExploreUrgentCandidate({required this.id, required this.candidate});
  final String id;
  final ExploreCandidate candidate;
}

/// The Marion County Explore programming engine.
///
/// Pure and synchronous (no I/O), exactly like [BackgroundDiscoveryScheduler]:
/// the runtime pushes fresh candidate pools in via [updateCandidates] as GPS/
/// content change, and calls [due] after each song to ask what (if anything)
/// should play next.
///
/// STAY LOCAL LONGER: every call to [due] tries, in order —
///   1. TEASER — a significant destination ahead but not yet close.
///   2. REVEAL — a genuine ahead-of-travel destination close enough to fully
///      reveal, expanded into a multi-segment travel-companion SESSION (see
///      [_buildSession]) — completely unaffected by everything below.
///   3. A LOCAL-COLOR BLOCK — when nothing is ahead of travel, [due] builds
///      and returns several consecutive local pieces about the CURRENT town
///      first (history, facts, events, historic sites, museums, attractions,
///      parks, springs, state parks, relevant wildlife/nature — whatever
///      exists), only reaching into a nearby town's content once the current
///      town's own unplayed content is genuinely exhausted, and only
///      reaching county-wide content once nearby towns are too — see
///      [_buildLocalColorBlock]/[_pickLocalColor]. The block plays entirely
///      back-to-back (no music between pieces); once it ends, the caller's
///      normal music fallback naturally plays — that's the "music is a
///      break after several local pieces" behavior, with no separate
///      "song gap" signal needed.
/// An empty local-color block (nothing anywhere is due) silently becomes
/// "just play music" — never silent, same contract as before.
///
/// No-repeat is exhaustion-based per category: an item won't repeat while
/// another unused item exists in its category. Local-color content
/// deliberately does NOT reset-and-repeat once a category is exhausted (spec:
/// "CRITICAL: do not repeat information already played") — a block simply
/// ends early and Explore falls through to music rather than repeating.
/// Ahead-of-travel categories (whereHeaded/events/teaser) are GPS-relative
/// and refreshed every tick, so they never auto-reset either way (a passed
/// destination simply drops out of the pool once it's no longer ahead).
///
/// [due] returns an empty list when there is truly nothing to say — the
/// caller falls back to normal content/music, exactly like
/// [BackgroundDiscoveryScheduler.due].
class ExploreRotationScheduler {
  ExploreRotationScheduler({this.djName = 'DJ Sunny', this.brand = 'Sunshine Travel Radio'});

  /// DJ Sunny — the same permanent Sunshine Travel Radio host used by
  /// [DjBanterScheduler] (`lib/features/radio/services/dj_banter_scheduler.dart`).
  /// Carried on every produced [AudioSegment]'s `artist` field, and used to
  /// fill the `{dj}`/`{station}` placeholders on the occasional Station ID
  /// pulled from the existing [kBanterTemplates] pool (see [_stationIdSegment])
  /// — no new voice/identity system, just the same pin threaded through here.
  final String djName;
  final String brand;

  /// Varied pre-arrival teaser phrasing (spec: "do not use the exact same
  /// teaser every time") — a plain round-robin, no [Random], so it stays
  /// deterministic and unit-testable. Which destination is being teased is
  /// carried by the candidate itself (image/nav still point at the real
  /// place); only the WORDING cycles here.
  static const List<String> _kTeaserPhrases = [
    "Something interesting is coming up ahead.",
    "You're heading toward a place worth knowing about.",
    "There's a story coming up worth slowing down for.",
    "Up ahead is somewhere with a story behind it.",
    "Keep going — something worth stopping for is coming up.",
    "There's more to discover a little further down the road.",
    "Coming up: somewhere with its own story to tell.",
    "You're getting closer to somewhere worth knowing about.",
  ];

  /// Opens a travel-companion SESSION (spec: TRAVEL TEASER, the first beat of
  /// teaser → intro → story → related → music). Deliberately a SEPARATE pool/
  /// cursor from [_kTeaserPhrases]/[_teaserPhraseCursor] — those are the
  /// standalone far-away single-line notice for a destination not yet close
  /// enough to reveal; reusing the same cursor risked the same or adjacent
  /// phrase surfacing twice in quick succession (once as a standalone tease,
  /// then again moments later opening that destination's own session).
  static const List<String> _kSessionOpenerPhrases = [
    "Looks like you're heading toward something pretty special.",
    "Your trip is taking you toward a place with quite a story.",
    "You're heading toward one of Marion County's special places.",
    "There's something worth slowing down for just ahead.",
    "Here's something worth knowing about where you're headed.",
    "You're about to pass somewhere with a real story behind it.",
  ];

  /// Natural transitions into a SESSION's RELATED content beat (spec section
  /// 5 — "find a meaningful connection," never "here's a random fact"). Two
  /// phrases per category so wording varies across sessions.
  static const Map<ExploreCategory, List<String>> _kRelatedTransitions = {
    ExploreCategory.wildlife: [
      "And that's not all — keep an eye out for the wildlife that calls this area home.",
      "There's more to it than the view, too — this area is home to some notable wildlife.",
    ],
    ExploreCategory.nature: [
      "There's a bit of natural history here worth knowing, too.",
      "The landscape itself has its own story.",
    ],
    ExploreCategory.geology: [
      "There's more beneath the surface, too.",
      "It's not just what you see above ground that's interesting here.",
    ],
    ExploreCategory.history: [
      "This place has more history behind it, too.",
      "There's more to the story of how this place came to be.",
    ],
  };

  /// DJ Sunny's intro into a local-color BLOCK (spec: "Explore should feel
  /// like DJ Sunny is hosting a LOCAL TRAVEL RADIO SHOW" — the block's own
  /// opening beat, distinct from [_kSessionOpenerPhrases] which opens an
  /// ahead-of-travel SESSION instead). Rotates so the same line doesn't
  /// repeat while others are unused.
  static const List<String> _kBlockOpenerPhrases = [
    "Hey, DJ Sunny here. You're traveling through a part of Marion County "
        "with a pretty interesting story.",
    "DJ Sunny back with you — here's something you might not know about "
        "this area.",
    "Alright, let's take a little local detour before the next song.",
    "You're riding with DJ Sunny, and I've got a few things worth knowing "
        "about right where you are.",
    "Speaking of where you are, there's a little local history worth "
        "knowing.",
    "While you're enjoying the road, here's what's happening around you.",
  ];

  /// Generic DJ Sunny connective tissue between two local-color pieces in the
  /// same block (spec: "CONNECT STORIES... the listener should feel like the
  /// information belongs together"). Used when the upcoming piece's category
  /// has no entry in [_kRelatedTransitions] (whereYouAre/events/county); when
  /// it does, that category-flavored phrase is preferred instead so the
  /// transition actually references what's coming next.
  static const List<String> _kBlockConnectorPhrases = [
    "That brings us to another part of the story.",
    "Here's something else you might not know about this area.",
    "Before we move on, here's a fun little fact.",
    "Now that we've covered that, there's a bit more worth knowing.",
    "Sticking around this area for a moment longer...",
    "There's more to this stretch of road than meets the eye.",
    "Let's keep the local tour going for a moment.",
    "One more thing worth knowing before we roll on.",
  ];

  /// Opens a fresh, stationary Explore session (spec: "PERSONALIZED GREETING
  /// -> LOCAL INFORMATION" — Explore is discovery-first, so this is the very
  /// first thing heard, before any song). Not tied to a `_pool`/`_played`
  /// no-repeat category like other content — it's synthesized directly from
  /// a place name (the same pattern [_sessionOpenerSegment]/[_introSegment]
  /// already use), and its own "don't repeat" requirement is wording variety
  /// (this cursor) plus the CALLER only ever invoking [greetingSegment] once
  /// per genuine session start (see `RadioEngineService._takeNext`'s
  /// cold-start check), never on a plain GPS update.
  static const List<String> _kGreetingTemplates = [
    "{greeting} to everyone listening here in {place}. Hope you're having a "
        "great day. Let's take a look around your corner of Marion County.",
    "{greeting}, folks in {place}. Let's see what's happening around you.",
    "{greeting} to everyone enjoying their time in {place}.",
    "{greeting}! Let's take a look around {place} and the rest of Marion "
        "County.",
  ];

  int _teaserPhraseCursor = 0;
  int _sessionOpenerCursor = 0;
  int _relatedTransitionCursor = 0;
  int _greetingCursor = 0;
  int _blockOpenerCursor = 0;
  int _blockConnectorCursor = 0;
  int _stationIdCursor = 0;

  Map<ExploreCategory, List<ExploreCandidate>> _pool = const {};
  final Map<ExploreCategory, Set<String>> _played = {};

  /// IDs already surfaced as an urgent interruption this trip — an urgent cue
  /// fires once, not on every tick while it stays close.
  final Set<String> _urgentFired = {};

  /// Replaces the candidate pool per category (runtime pushes as GPS/content
  /// change). Does not touch play history or cycle position.
  void updateCandidates(Map<ExploreCategory, List<ExploreCandidate>> pool) {
    _pool = pool;
  }

  /// Whether [id] has already aired in [category] since the last reset —
  /// exposed for tests/telemetry.
  bool hasPlayed(ExploreCategory category, String id) =>
      (_played[category] ?? const {}).contains(id);

  /// A defensive copy of everything played so far, per category — persisted
  /// by the runtime (SharedPreferences) so history survives an app restart.
  /// This class itself stays pure/synchronous; it never touches storage.
  Map<ExploreCategory, Set<String>> snapshotPlayed() => {
        for (final e in _played.entries) e.key: Set<String>.from(e.value),
      };

  /// Seeds already-played history from a previous session (merges, does not
  /// overwrite) — called once at startup, before the first [due]/[urgent].
  void restorePlayed(Map<ExploreCategory, Set<String>> seed) {
    for (final entry in seed.entries) {
      (_played[entry.key] ??= {}).addAll(entry.value);
    }
  }

  /// LOCAL FIRST → NEARBY SECOND: ranks by type-based
  /// [ExploreCandidate.aheadPriority] first (e.g. a park outranks a town),
  /// then by [ExploreCandidate.distanceMeters] (closer wins) as the
  /// tiebreak — so within a category/tier, content in the traveler's
  /// current area is always tried before content from a farther-out nearby
  /// town, which is tried before non-geographic content (no distance set,
  /// sorts last). Candidates with the default (not-applicable) priority
  /// compare equal and fall straight through to the distance comparison.
  static int _compareLocalFirst(ExploreCandidate a, ExploreCandidate b) {
    final byPriority = a.aheadPriority.compareTo(b.aheadPriority);
    if (byPriority != 0) return byPriority;
    final ad = a.distanceMeters ?? double.infinity;
    final bd = b.distanceMeters ?? double.infinity;
    return ad.compareTo(bd);
  }

  /// Ranks UNSEEN candidates across several categories together (local-first,
  /// per [_compareLocalFirst]) — used only for the ahead-of-travel groups
  /// (teaser/whereHeaded/events-as-reveal), which never repeat once aired.
  ExploreCandidate? _pickAheadAcross(List<ExploreCategory> cats) {
    final unseen = <ExploreCandidate>[];
    for (final cat in cats) {
      final all =
          (_pool[cat] ?? const []).where((c) => c.isPlayable && c.isAheadOfTravel);
      final played = _played[cat] ?? const <String>{};
      unseen.addAll(all.where((c) => !played.contains(c.id)));
    }
    if (unseen.isEmpty) return null;
    unseen.sort(_compareLocalFirst);
    return unseen.first;
  }

  /// Marks [c] played, permanently, for the rest of the trip — no
  /// reset-and-repeat branch (that was the old tier-priority model's
  /// behavior; under STAY LOCAL LONGER, "CRITICAL: do not repeat
  /// information already played" applies uniformly to every category, not
  /// just the sticky ahead-of-travel ones).
  void _markPlayed(ExploreCandidate c) {
    (_played[c.category] ??= {}).add(c.id);
    if (c.category == ExploreCategory.teaser) _teaserPhraseCursor++;
  }

  /// STAY LOCAL LONGER (spec): tries ahead-of-travel first (unchanged —
  /// [_pickAheadAcross] here, exactly as before), then builds a local-color
  /// BLOCK of several consecutive pieces about the current town, only
  /// reaching a nearby town's/county-wide content once the current town's
  /// own unplayed content is genuinely exhausted — see [_buildLocalColorBlock].
  /// Returns an empty list only when there is truly nothing anywhere; the
  /// caller falls back to music either way, same "never silent" contract.
  List<AudioSegment> due() {
    final teaser = _pickAheadAcross([ExploreCategory.teaser]);
    if (teaser != null) {
      final segment = _toSegment(teaser, resumeAfter: true);
      _markPlayed(teaser);
      return [segment];
    }
    final reveal = _pickAheadAcross(
        [ExploreCategory.whereHeaded, ExploreCategory.events]);
    if (reveal != null) return _buildSession(reveal);

    return _buildLocalColorBlock();
  }

  /// The single BEST candidate [due] would pick right now, without mutating
  /// any state — exposed for tests/telemetry. Same ahead-of-travel-first
  /// priority as [due], but doesn't expand a REVEAL into a session or a
  /// local-color pick into a full block (both are [due]-specific mechanics).
  ExploreCandidate? select() =>
      _pickAheadAcross([ExploreCategory.teaser]) ??
      _pickAheadAcross([ExploreCategory.whereHeaded, ExploreCategory.events]) ??
      _pickLocalColor();

  /// Locality tiers for STAY LOCAL LONGER: the traveler's CURRENT TOWN first,
  /// a NEARBY town second, county-wide/generic content last — spec: "Only
  /// after the relevant UNUSED content for that town has been reasonably
  /// exhausted should Explore expand outward."
  static const List<ExploreCategory> _kLocalColorCategories = [
    ExploreCategory.whereYouAre,
    ExploreCategory.events,
    ExploreCategory.wildlife,
    ExploreCategory.nature,
    ExploreCategory.geology,
    ExploreCategory.history,
    ExploreCategory.county,
  ];

  static const List<ExploreCategory> _kWildlifeCategories = [
    ExploreCategory.wildlife,
    ExploreCategory.nature,
    ExploreCategory.geology,
  ];

  /// Matches explore_providers.dart's `_kWhereYouAreTownMaxMeters` (~10mi) —
  /// the existing, already-tuned "is this my town" radius, intentionally
  /// reused rather than inventing a second one.
  static const double _kCurrentTownRadiusMeters = 10 * 1609.344;

  static int _tierOf(ExploreCandidate c) {
    final d = c.distanceMeters;
    if (d == null) return 2; // county-wide/generic — no location at all
    if (d <= _kCurrentTownRadiusMeters) return 0; // current town
    return 1; // nearby town
  }

  /// TIER beats TYPE beats raw distance — the direct fix for "a neighboring
  /// town's park (low type-priority) outranking my own town's history (no
  /// type-priority) purely because of what KIND of place it is." Used only
  /// for local-color selection; [_pickAheadAcross] (ahead-of-travel) keeps
  /// using [_compareLocalFirst] (type-first) completely unchanged — moving
  /// Explore is unaffected by this comparator existing.
  static int _compareTownFirst(ExploreCandidate a, ExploreCandidate b) {
    final byTier = _tierOf(a).compareTo(_tierOf(b));
    if (byTier != 0) return byTier;
    final byPriority = a.aheadPriority.compareTo(b.aheadPriority);
    if (byPriority != 0) return byPriority;
    final ad = a.distanceMeters ?? double.infinity;
    final bd = b.distanceMeters ?? double.infinity;
    return ad.compareTo(bd);
  }

  /// The single best UNSEEN local-color candidate right now, tier-first (see
  /// [_compareTownFirst]), or null once every relevant category is
  /// exhausted. Deliberately NO repeat-fallback — spec: "CRITICAL: do not
  /// repeat information already played" — once everything is genuinely
  /// exhausted, [_buildLocalColorBlock] simply ends the block early rather
  /// than repeating (the direct fix for the old fallback loop silently
  /// repeating `whereYouAre` forever instead of ever reaching `events`/
  /// `county`/`history` for their own fresh content).
  ExploreCandidate? _pickLocalColor([List<ExploreCategory>? only]) {
    final unseen = <ExploreCandidate>[];
    for (final cat in only ?? _kLocalColorCategories) {
      final played = _played[cat] ?? const <String>{};
      for (final c in _pool[cat] ?? const <ExploreCandidate>[]) {
        // Only `events` ever mixes in isAheadOfTravel:true candidates (an
        // ahead-cone event reserved for _pickAheadAcross's own reveal) —
        // every other category defaults to true and must NOT be excluded.
        if (cat == ExploreCategory.events && c.isAheadOfTravel) continue;
        if (c.isPlayable && !played.contains(c.id)) unseen.add(c);
      }
    }
    if (unseen.isEmpty) return null;
    unseen.sort(_compareTownFirst);
    return unseen.first;
  }

  static const int _kMaxLocalColorBlockSize = 8; // "several pieces" — tunable
  static const int _kWildlifeGuaranteeEveryNPicks = 3; // soft guarantee, tunable

  /// How often (in local-color picks) an occasional Station ID airs inside a
  /// block — spec: "occasionally," explicitly NOT after every segment.
  static const int _kStationIdEveryNPicks = 5;

  /// Builds the actual back-to-back local-color BLOCK [due] returns: several
  /// consecutive spoken pieces, no music between them (spec: "Music should
  /// be a BREAK after several local content pieces, not the reason to leave
  /// the current town") — the block simply ends once fresh content runs out
  /// or the size cap is hit, and the caller's normal music fallback plays
  /// once the queued block drains. Reuses the exact same "a due() call can
  /// return multiple segments, queued back-to-back" mechanism [_buildSession]
  /// already proved — no engine/queue changes needed.
  ///
  /// Wildlife/nature/geology are woven in via a soft guarantee
  /// ([_kWildlifeGuaranteeEveryNPicks]) rather than a separate cycle slot —
  /// matching the spec's own example, which places wildlife/nature within a
  /// rich local block rather than on a rigid alternating cadence, while
  /// still ensuring it's never starved out of a long block entirely.
  ///
  /// PRESENTATION (spec "MAKE IT SOUND LIKE RADIO, NOT A DATABASE"): the
  /// GPS/content selection above is completely unchanged — this only wraps
  /// it with DJ Sunny's voice. The block opens with a DJ Sunny intro
  /// ([_blockOpenerSegment]), each subsequent piece is preceded by a short
  /// connective line ([_blockConnectorSegment]) instead of just cutting
  /// straight to the next content record, and an occasional Station ID
  /// ([_stationIdSegment]) airs every [_kStationIdEveryNPicks] picks — never
  /// after every single piece.
  List<AudioSegment> _buildLocalColorBlock() {
    final segments = <AudioSegment>[];
    var picksSinceWildlife = 0;
    var pickCount = 0;
    for (var i = 0; i < _kMaxLocalColorBlockSize; i++) {
      ExploreCandidate? pick;
      if (picksSinceWildlife >= _kWildlifeGuaranteeEveryNPicks) {
        pick = _pickLocalColor(_kWildlifeCategories);
      }
      pick ??= _pickLocalColor();
      if (pick == null) break; // nothing fresh left anywhere -- end, never repeat

      segments.add(
        segments.isEmpty ? _blockOpenerSegment() : _blockConnectorSegment(pick),
      );
      segments.add(_toSegment(pick, resumeAfter: true));
      _markPlayed(pick);
      pickCount++;
      picksSinceWildlife =
          _kWildlifeCategories.contains(pick.category) ? 0 : picksSinceWildlife + 1;

      if (pickCount % _kStationIdEveryNPicks == 0) {
        segments.add(_stationIdSegment());
      }
    }
    return segments;
  }

  /// DJ Sunny's opening line for a local-color block — the "welcome to this
  /// local segment" beat the plain content-record playback never had.
  AudioSegment _blockOpenerSegment() {
    final text = _kBlockOpenerPhrases[_blockOpenerCursor % _kBlockOpenerPhrases.length];
    _blockOpenerCursor++;
    return AudioSegment(
      id: 'explore:block-opener:${DateTime.now().microsecondsSinceEpoch}',
      title: 'DJ Sunny',
      artist: djName,
      type: AudioSegmentType.gpsNarration,
      priority: PlaybackPriority.scheduledAnnouncement,
      spokenText: text,
      tags: const ['explore', 'dj_glue'],
      interruptible: false,
      resumeAfter: true,
    );
  }

  /// A short DJ Sunny line connecting the piece that just aired to [next] —
  /// prefers [next]'s own category-flavored transition (the same pool
  /// [_transitionSegment] uses for sessions) so the line actually reads as
  /// "here's what's coming," falling back to the generic connector pool for
  /// categories ([ExploreCategory.whereYouAre]/[events]/[county]) that don't
  /// have one.
  AudioSegment _blockConnectorSegment(ExploreCandidate next) {
    final categoryPhrases = _kRelatedTransitions[next.category];
    final String text;
    if (categoryPhrases != null && categoryPhrases.isNotEmpty) {
      text = categoryPhrases[_relatedTransitionCursor % categoryPhrases.length];
      _relatedTransitionCursor++;
    } else {
      text = _kBlockConnectorPhrases[
          _blockConnectorCursor % _kBlockConnectorPhrases.length];
      _blockConnectorCursor++;
    }
    return AudioSegment(
      id: 'explore:block-connector:${next.category.name}:${next.id}:'
          '${DateTime.now().microsecondsSinceEpoch}',
      title: 'DJ Sunny',
      artist: djName,
      type: AudioSegmentType.gpsNarration,
      priority: PlaybackPriority.scheduledAnnouncement,
      spokenText: text,
      tags: const ['explore', 'dj_glue'],
      interruptible: false,
      resumeAfter: true,
    );
  }

  /// An occasional Station ID, reusing the existing DJ Banter Engine's own
  /// [kBanterTemplates] pool ([BanterSituation.stationId]) rather than a new
  /// phrase system — the same pool [DjBanterScheduler] pulls from between
  /// songs. Rotates through every `all`-station template so wording varies.
  AudioSegment _stationIdSegment() {
    final templates = kBanterTemplates
        .where((t) => t.situation == BanterSituation.stationId && t.station == DjStation.all)
        .toList();
    final text = templates.isEmpty
        ? "You're listening to $brand."
        : BanterEngine.fill(
            templates[_stationIdCursor % templates.length].text,
            BanterContext(station: brand, djName: djName),
          );
    _stationIdCursor++;
    return AudioSegment(
      id: 'explore:stationid:${DateTime.now().microsecondsSinceEpoch}',
      title: 'Station ID',
      artist: djName,
      type: AudioSegmentType.stationIdentification,
      priority: PlaybackPriority.stationIdentification,
      spokenText: text,
      tags: const ['explore', 'station_id'],
      interruptible: false,
      resumeAfter: true,
    );
  }

  /// Builds a travel-companion SESSION around a genuine ahead-of-travel
  /// REVEAL (spec: TRAVEL TEASER → DESTINATION INTRODUCTION → DESTINATION
  /// STORY → RELATED CONTENT (only when relevant) → MUSIC). At most 5
  /// segments; steps that don't apply are simply omitted, never invented.
  ///
  /// NOTE (accepted trade-off, not fixed by this method): `checkUrgent()`
  /// (radio_session_provider.dart) runs on every GPS tick, independent of
  /// [due]'s song-boundary cadence. If a destination crosses the closer
  /// "urgent" threshold before the current song even ends, `urgent()` can
  /// fire first — that destination gets today's flat single-line urgent
  /// narration instead of a session (a missed session, not a repeat; see the
  /// no-double-fire guard added to [urgent] below for the repeat case).
  /// Fixing the ordering would mean making session-building event-driven
  /// rather than song-boundary-driven, which is outside this change's scope
  /// (spec: do not rebuild the audio system). Also: every segment here is
  /// `interruptible:false`, so a *different* destination's urgent interrupt
  /// can be delayed until the whole session drains — the same kind of
  /// behavior as today's single segment, just larger in the worst case.
  List<AudioSegment> _buildSession(ExploreCandidate reveal) {
    final segments = <AudioSegment>[
      _sessionOpenerSegment(reveal),
    ];

    final intro = _introSegment(reveal);
    if (intro != null) segments.add(intro);

    segments.add(_toSegment(reveal, resumeAfter: true));
    _markPlayed(reveal);

    final related = _relatedForSession(reveal.sessionKey);
    if (related != null) {
      final transition = _transitionSegment(related);
      if (transition != null) segments.add(transition);
      segments.add(_toSegment(related, resumeAfter: true));
      _markPlayed(related);
    }

    return segments;
  }

  /// Carries [reveal]'s own imageUrl/location/tellMeMoreContext (per the
  /// "image, name, narration, and NAVIGATE target can never drift apart"
  /// contract on [ExploreCandidate.imageUrl]) so the now-playing card already
  /// shows the destination from the very first beat of the session, not just
  /// once the story segment starts a beat or two later.
  AudioSegment _sessionOpenerSegment(ExploreCandidate reveal) {
    final text =
        _kSessionOpenerPhrases[_sessionOpenerCursor % _kSessionOpenerPhrases.length];
    _sessionOpenerCursor++;
    return AudioSegment(
      id: 'explore:session-opener:${DateTime.now().microsecondsSinceEpoch}',
      title: reveal.title,
      artist: djName,
      type: AudioSegmentType.gpsNarration,
      priority: PlaybackPriority.scheduledAnnouncement,
      imageUrl: reveal.imageUrl,
      spokenText: text,
      location: reveal.hasDestination
          ? GeoPoint(latitude: reveal.latitude!, longitude: reveal.longitude!)
          : null,
      tags: ['explore', 'session_opener'],
      interruptible: false,
      resumeAfter: true,
      tellMeMoreContext: reveal.tellMeMoreContext,
    );
  }

  /// "You're about X miles from {title}." — always spoken fresh (never an
  /// [ExploreCandidate.audioUrl], even when the destination itself has
  /// recorded story audio; [_toSegment] treats audio/spokenText as mutually
  /// exclusive on one segment, so the intro must be its own segment).
  /// Returns null (no invented distance) when [ExploreCandidate.distanceMeters]
  /// isn't set — doesn't happen in practice for a REVEAL pick, but this stays
  /// defensive per spec: "Do not invent distances."
  AudioSegment? _introSegment(ExploreCandidate c) {
    final meters = c.distanceMeters;
    if (meters == null) return null;
    final miles = meters / 1609.344;
    final text = "You're about ${miles.toStringAsFixed(miles < 10 ? 1 : 0)} "
        "miles from ${c.title}.";
    return AudioSegment(
      id: 'explore:intro:${c.category.name}:${c.id}:'
          '${DateTime.now().microsecondsSinceEpoch}',
      title: c.title,
      artist: djName,
      type: AudioSegmentType.gpsNarration,
      priority: PlaybackPriority.scheduledAnnouncement,
      imageUrl: c.imageUrl,
      spokenText: text,
      location: c.hasDestination
          ? GeoPoint(latitude: c.latitude!, longitude: c.longitude!)
          : null,
      tags: ['explore', c.category.name],
      interruptible: false,
      resumeAfter: true,
      tellMeMoreContext: c.tellMeMoreContext,
    );
  }

  /// A candidate genuinely ABOUT the same destination as [sessionKey] (spec:
  /// a MEANINGFUL connection, never a random one) — checked across
  /// WILDLIFE → NATURE → GEOLOGY → HISTORY, in that priority order (HISTORY
  /// is deliberately included here even though [_selectWildlife]'s own cycle
  /// slot doesn't loop it — a destination's related history is a valid
  /// connection per spec section 4, not a bug to reconcile with the
  /// unrelated WILDLIFE cycle slot). At most one, unplayed, per session.
  ExploreCandidate? _relatedForSession(String? sessionKey) {
    if (sessionKey == null) return null;
    for (final cat in [
      ExploreCategory.wildlife,
      ExploreCategory.nature,
      ExploreCategory.geology,
      ExploreCategory.history,
    ]) {
      final played = _played[cat] ?? const <String>{};
      for (final c in _pool[cat] ?? const <ExploreCandidate>[]) {
        if (c.sessionKey == sessionKey && c.isPlayable && !played.contains(c.id)) {
          return c;
        }
      }
    }
    return null;
  }

  AudioSegment? _transitionSegment(ExploreCandidate related) {
    final phrases = _kRelatedTransitions[related.category];
    if (phrases == null || phrases.isEmpty) return null;
    final text = phrases[_relatedTransitionCursor % phrases.length];
    _relatedTransitionCursor++;
    return AudioSegment(
      id: 'explore:transition:${related.category.name}:${related.id}:'
          '${DateTime.now().microsecondsSinceEpoch}',
      title: related.title,
      artist: djName,
      type: AudioSegmentType.gpsNarration,
      priority: PlaybackPriority.scheduledAnnouncement,
      imageUrl: related.imageUrl,
      spokenText: text,
      location: related.hasDestination
          ? GeoPoint(latitude: related.latitude!, longitude: related.longitude!)
          : null,
      tags: ['explore', related.category.name],
      interruptible: false,
      resumeAfter: true,
      tellMeMoreContext: related.tellMeMoreContext,
    );
  }

  /// A personalized time-of-day + place greeting ("Good afternoon to
  /// everyone listening here in Ocklawaha..."), varied via a round-robin
  /// cursor (never the same wording twice while others are unused — spec:
  /// "Do NOT use the exact same greeting every time"). [place] is a town
  /// name or "`<County> County`" fallback, resolved by the caller
  /// (`playerLocationContextProvider`) — never invented here.
  AudioSegment greetingSegment(String place) {
    final template =
        _kGreetingTemplates[_greetingCursor % _kGreetingTemplates.length];
    _greetingCursor++;
    final text = template
        .replaceFirst('{greeting}', greetingForTime(DateTime.now()))
        .replaceFirst('{place}', place);
    return AudioSegment(
      id: 'explore:greeting:${DateTime.now().microsecondsSinceEpoch}',
      title: 'Welcome',
      artist: djName,
      type: AudioSegmentType.gpsNarration,
      priority: PlaybackPriority.scheduledAnnouncement,
      spokenText: text,
      tags: const ['explore', 'greeting'],
      interruptible: false,
      resumeAfter: true,
    );
  }

  /// Checks whether an important location just became relevant enough to
  /// jump the queue (spec section 7). [candidate] is the nearest current
  /// WHAT'S AHEAD item, already resolved by the runtime; [isCloseEnough] is
  /// the runtime's own "worth interrupting for" test (e.g. under a mile, or
  /// a couple of minutes out) so this class stays free of GPS/ETA math.
  /// Fires at most once per candidate id per trip, and marks it played so a
  /// later [due] call in the same category won't immediately repeat it.
  ///
  /// Also refuses to fire for a candidate [due] already narrated (e.g. as
  /// part of a session — see [_buildSession]). `checkUrgent()` in
  /// radio_session_provider.dart runs on every GPS tick and reads the pool
  /// directly, unfiltered by [_played] — without this check, a destination
  /// already told via the normal cycle could be narrated a SECOND time the
  /// moment it crosses the closer urgent threshold (the exact "the story
  /// plays again" bug this feature must not have). Safe/permanent because
  /// whereHeaded/events (the only categories [urgent] is ever called with)
  /// are sticky — [_played] for them is never cleared mid-trip.
  AudioSegment? urgent(ExploreCandidate? candidate, {required bool isCloseEnough}) {
    if (candidate == null || !candidate.isPlayable || !isCloseEnough) return null;
    if (_urgentFired.contains(candidate.id)) return null;
    if (hasPlayed(candidate.category, candidate.id)) return null;
    _urgentFired.add(candidate.id);
    final segment = _toSegment(candidate, resumeAfter: true, urgent: true);
    _markPlayed(candidate);
    return segment;
  }

  /// New trip — clears play history and urgent memory. Does NOT clear
  /// anything persisted by the runtime — that's [snapshotPlayed]/
  /// [restorePlayed]'s concern, outside this class.
  void reset() {
    _played.clear();
    _urgentFired.clear();
    _teaserPhraseCursor = 0;
    _sessionOpenerCursor = 0;
    _relatedTransitionCursor = 0;
    _greetingCursor = 0;
    _blockOpenerCursor = 0;
    _blockConnectorCursor = 0;
    _stationIdCursor = 0;
  }

  AudioSegment _toSegment(
    ExploreCandidate c, {
    required bool resumeAfter,
    bool urgent = false,
  }) {
    final hasAudio = (c.audioUrl ?? '').trim().isNotEmpty;
    // Teasers never speak the candidate's own spokenText (a placeholder just
    // to satisfy isPlayable) — always the varied phrasing, so the same
    // wording doesn't repeat while other phrases are unused.
    final spokenText = c.category == ExploreCategory.teaser
        ? _kTeaserPhrases[_teaserPhraseCursor % _kTeaserPhrases.length]
        : c.spokenText;
    return AudioSegment(
      id: 'explore:${urgent ? 'urgent:' : ''}${c.category.name}:${c.id}:'
          '${DateTime.now().microsecondsSinceEpoch}',
      title: c.title.isEmpty ? c.category.label : c.title,
      artist: djName,
      type: AudioSegmentType.gpsNarration,
      priority: PlaybackPriority.scheduledAnnouncement,
      imageUrl: c.imageUrl,
      audioUrl: hasAudio ? c.audioUrl : null,
      spokenText: hasAudio ? null : spokenText,
      location: c.hasDestination
          ? GeoPoint(latitude: c.latitude!, longitude: c.longitude!)
          : null,
      tags: ['explore', c.category.name],
      interruptible: false,
      resumeAfter: resumeAfter,
      tellMeMoreContext: c.tellMeMoreContext,
    );
  }
}
