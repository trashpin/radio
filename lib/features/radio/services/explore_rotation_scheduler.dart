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
/// Fixed 3-step CYCLE, not a priority scan: every call to [due] advances one
/// position, wrapping around —
///   0. INFORMATION (a teaser, an ahead-of-travel reveal, or a general local
///      story — whichever is available)
///   1. WILDLIFE/ANIMAL (a guaranteed slot every cycle, not conditional on
///      whether anything was ahead)
///   2. SONG GAP — [due] returns null so the caller's normal music fallback
///      plays exactly one song, then the cycle resumes at INFORMATION.
/// An empty INFORMATION or WILDLIFE slot silently becomes "one extra song"
/// rather than blocking or borrowing from a later position — the cycle
/// position always advances regardless of what (if anything) was found.
///
/// No-repeat is exhaustion-based per category, not a play-count cooldown: an
/// item won't repeat while another unused item exists in its category: once
/// every item in a category has aired, that category's played history
/// resets and it may repeat — EXCEPT the ahead-of-travel categories
/// (whereHeaded/events/teaser), which are GPS-relative and refreshed every
/// tick, so they never auto-reset (a passed destination simply drops out of
/// the pool once it's no longer ahead, rather than being eligible to replay
/// while still being approached).
///
/// [due] returns an empty list when there is truly nothing to say — the
/// caller falls back to normal content/music, exactly like
/// [BackgroundDiscoveryScheduler.due]. When INFORMATION lands on a genuine
/// ahead-of-travel destination reveal, [due] instead returns a small
/// travel-companion SESSION (teaser → intro → story → related content, when
/// relevant → music) — see [ExploreRotationScheduler._buildSession].
class ExploreRotationScheduler {
  ExploreRotationScheduler();

  static const Set<ExploreCategory> _kStickyNoReset = {
    ExploreCategory.whereHeaded,
    ExploreCategory.events,
    ExploreCategory.teaser,
  };

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

  int _cyclePosition = 0; // 0=INFORMATION, 1=WILDLIFE, 2=SONG GAP
  int _teaserPhraseCursor = 0;
  int _sessionOpenerCursor = 0;
  int _relatedTransitionCursor = 0;

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

  ExploreCandidate? _pick(ExploreCategory cat) {
    final all = (_pool[cat] ?? const []).where((c) => c.isPlayable).toList();
    if (all.isEmpty) return null;
    final played = _played[cat] ?? const <String>{};
    final unseen = all.where((c) => !played.contains(c.id)).toList()
      ..sort(_compareLocalFirst);
    if (unseen.isNotEmpty) return unseen.first;
    // Every item in this category has aired. Sticky (ahead-of-travel)
    // categories stay quiet rather than repeat; everything else may loop
    // back now that the whole pool has genuinely been exhausted.
    if (_kStickyNoReset.contains(cat)) return null;
    return (all..sort(_compareLocalFirst)).first;
  }

  /// Like [_pick], but ranks UNSEEN candidates across several categories
  /// together (local-first, per [_compareLocalFirst]) rather than trying one
  /// category to exhaustion before the next. Only used for the sticky
  /// ahead-of-travel groups, which never reset, so there's no
  /// exhaustion-reset branch here.
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

  void _markPlayed(ExploreCandidate c) {
    final played = _played[c.category] ??= {};
    final all = (_pool[c.category] ?? const []).where((x) => x.isPlayable);
    final allAlreadyPlayed =
        all.every((x) => played.contains(x.id) || x.id == c.id);
    if (allAlreadyPlayed && !_kStickyNoReset.contains(c.category)) {
      played.clear();
    }
    played.add(c.id);
    if (c.category == ExploreCategory.teaser) _teaserPhraseCursor++;
  }

  /// The segment(s) for the CURRENT cycle position, then advances to the next
  /// position regardless of whether anything was found (an empty INFORMATION/
  /// WILDLIFE slot silently becomes one extra song). Usually a single-item
  /// (or empty) list; when INFORMATION lands on a genuine ahead-of-travel
  /// REVEAL, this instead returns a whole travel-companion SESSION — see
  /// [_buildSession] — so the caller can queue them back-to-back before the
  /// next song plays (spec: "make Explore feel like a travel companion").
  List<AudioSegment> due() {
    final segments = <AudioSegment>[];
    switch (_cyclePosition) {
      case 0:
        final picked = _selectInformationDetailed();
        final pick = picked.candidate;
        if (pick != null) {
          if (picked.isReveal) {
            segments.addAll(_buildSession(pick));
          } else {
            segments.add(_toSegment(pick, resumeAfter: true));
            _markPlayed(pick);
          }
        }
        break;
      case 1:
        final pick = _selectWildlife();
        if (pick != null) {
          segments.add(_toSegment(pick, resumeAfter: true));
          _markPlayed(pick);
        }
        break;
      default:
        break; // song gap
    }
    _cyclePosition = (_cyclePosition + 1) % 3;
    return segments;
  }

  /// The candidate [due] would pick right now, without mutating any state —
  /// exposed for tests/telemetry. Byte-identical contract to before: still a
  /// single candidate, even though a REVEAL pick now expands into a full
  /// session inside [due] itself.
  ExploreCandidate? select() {
    switch (_cyclePosition) {
      case 0:
        return _selectInformationDetailed().candidate;
      case 1:
        return _selectWildlife();
      default:
        return null; // song gap
    }
  }

  /// LOCAL FIRST → NEARBY SECOND → COUNTY LAST:
  ///   1. teaser — a significant destination ahead but not yet close.
  ///   2. genuinely ahead-of-travel + close enough to fully reveal (ranked
  ///      local-first among themselves — see [_pickAheadAcross]). Flagged
  ///      `isReveal: true` — the ONLY case [due] expands into a session.
  ///   3. WHERE YOU ARE — the current park/spring/town PLUS other nearby
  ///      parks/springs/attractions/historic sites, closest (and highest
  ///      type-priority) first — so the current town/area is exhausted
  ///      before farther nearby towns are ever reached (emergent from
  ///      [_compareLocalFirst]'s sort, not a separate category per band).
  ///   4. EVENTS — current-town events before farther nearby-town events,
  ///      same local-first distance sort. NOT a reveal (a merely-nearby
  ///      event, not one detected ahead-of-travel) even though it shares a
  ///      category with step 2's ahead-cone events.
  ///   5. COUNTY — county-wide facts/history, the true last resort.
  ///   6. HISTORY — broader, non-town-specific history content.
  ({ExploreCandidate? candidate, bool isReveal}) _selectInformationDetailed() {
    final teaser = _pickAheadAcross([ExploreCategory.teaser]);
    if (teaser != null) return (candidate: teaser, isReveal: false);
    final reveal = _pickAheadAcross(
        [ExploreCategory.whereHeaded, ExploreCategory.events]);
    if (reveal != null) return (candidate: reveal, isReveal: true);
    for (final cat in [
      ExploreCategory.whereYouAre,
      ExploreCategory.events,
      ExploreCategory.county,
      ExploreCategory.history,
    ]) {
      final pick = _pick(cat);
      if (pick != null) return (candidate: pick, isReveal: false);
    }
    return (candidate: null, isReveal: false);
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

  ExploreCandidate? _selectWildlife() {
    for (final cat in [
      ExploreCategory.wildlife,
      ExploreCategory.nature,
      ExploreCategory.geology,
    ]) {
      final pick = _pick(cat);
      if (pick != null) return pick;
    }
    return null;
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

  /// New trip — clears play history, urgent memory, and cycle position (a
  /// fresh trip always restarts at INFORMATION). Does NOT clear anything
  /// persisted by the runtime — that's [snapshotPlayed]/[restorePlayed]'s
  /// concern, outside this class.
  void reset() {
    _played.clear();
    _urgentFired.clear();
    _cyclePosition = 0;
    _teaserPhraseCursor = 0;
    _sessionOpenerCursor = 0;
    _relatedTransitionCursor = 0;
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
