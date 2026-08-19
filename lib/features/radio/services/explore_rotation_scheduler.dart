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
  history;

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
  });

  final String id;
  final ExploreCategory category;
  final String title;
  final String? audioUrl;
  final String? spokenText;
  final TellMeMoreContext? tellMeMoreContext;

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
/// Fixed priority TIERS, scanned fresh on every call (no persisted cursor —
/// a category doesn't get "its turn" once per lap, it's simply the
/// highest-priority tier with something unused to say, every time):
///   1. WHAT'S AHEAD    (whereHeaded, events)
///   2. WILDLIFE/NATURE (wildlife, nature, geology)
///   3. WHERE YOU ARE   (whereYouAre, county)
///   4. HISTORY         (history)
/// Within a tier, categories are tried in the order listed (e.g. a specific
/// WHERE YOU ARE beats the broader county fallback).
///
/// No-repeat is exhaustion-based per category, not a play-count cooldown: an
/// item won't repeat while another unused item exists in its category: once
/// every item in a category has aired, that category's played history
/// resets and it may repeat — EXCEPT the ahead-of-travel categories
/// (whereHeaded/events), which are GPS-relative and refreshed every tick, so
/// they never auto-reset (a passed destination simply drops out of the pool
/// once it's no longer ahead, rather than being eligible to replay while
/// still being approached).
///
/// Returns null when there is truly nothing to say anywhere — the caller
/// falls back to normal content/music, exactly like
/// [BackgroundDiscoveryScheduler.due].
class ExploreRotationScheduler {
  ExploreRotationScheduler();

  static const List<List<ExploreCategory>> _kTiers = [
    [ExploreCategory.whereHeaded, ExploreCategory.events],
    [ExploreCategory.wildlife, ExploreCategory.nature, ExploreCategory.geology],
    [ExploreCategory.whereYouAre, ExploreCategory.county],
    [ExploreCategory.history],
  ];

  static const Set<ExploreCategory> _kStickyNoReset = {
    ExploreCategory.whereHeaded,
    ExploreCategory.events,
  };

  Map<ExploreCategory, List<ExploreCandidate>> _pool = const {};
  final Map<ExploreCategory, Set<String>> _played = {};

  /// IDs already surfaced as an urgent interruption this trip — an urgent cue
  /// fires once, not on every tick while it stays close.
  final Set<String> _urgentFired = {};

  /// Replaces the candidate pool per category (runtime pushes as GPS/content
  /// change). Does not touch play history.
  void updateCandidates(Map<ExploreCategory, List<ExploreCandidate>> pool) {
    _pool = pool;
  }

  /// Whether [id] has already aired in [category] since the last reset —
  /// exposed for tests/telemetry.
  bool hasPlayed(ExploreCategory category, String id) =>
      (_played[category] ?? const {}).contains(id);

  ExploreCandidate? _pick(ExploreCategory cat) {
    final all = (_pool[cat] ?? const []).where((c) => c.isPlayable).toList();
    if (all.isEmpty) return null;
    final played = _played[cat] ?? const <String>{};
    final unseen = all.where((c) => !played.contains(c.id)).toList();
    if (unseen.isNotEmpty) return unseen.first;
    // Every item in this category has aired. Sticky (ahead-of-travel)
    // categories stay quiet rather than repeat; everything else may loop
    // back now that the whole pool has genuinely been exhausted.
    if (_kStickyNoReset.contains(cat)) return null;
    return all.first;
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
  }

  /// The next segment, in strict tier priority, re-evaluated from the top
  /// every call. Null when every tier is either empty or fully exhausted
  /// (sticky) right now.
  AudioSegment? due() {
    final pick = select();
    if (pick == null) return null;
    _markPlayed(pick);
    return _toSegment(pick, resumeAfter: true);
  }

  /// The candidate [due] would pick right now, without mutating any state —
  /// exposed for tests/telemetry.
  ExploreCandidate? select() {
    for (final tier in _kTiers) {
      for (final cat in tier) {
        final pick = _pick(cat);
        if (pick != null) return pick;
      }
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
  AudioSegment? urgent(ExploreCandidate? candidate, {required bool isCloseEnough}) {
    if (candidate == null || !candidate.isPlayable || !isCloseEnough) return null;
    if (_urgentFired.contains(candidate.id)) return null;
    _urgentFired.add(candidate.id);
    _markPlayed(candidate);
    return _toSegment(candidate, resumeAfter: true, urgent: true);
  }

  /// New trip — clears play history and urgent memory.
  void reset() {
    _played.clear();
    _urgentFired.clear();
  }

  AudioSegment _toSegment(
    ExploreCandidate c, {
    required bool resumeAfter,
    bool urgent = false,
  }) {
    final hasAudio = (c.audioUrl ?? '').trim().isNotEmpty;
    return AudioSegment(
      id: 'explore:${urgent ? 'urgent:' : ''}${c.category.name}:${c.id}:'
          '${DateTime.now().microsecondsSinceEpoch}',
      title: c.title.isEmpty ? c.category.label : c.title,
      type: AudioSegmentType.gpsNarration,
      priority: PlaybackPriority.scheduledAnnouncement,
      imageUrl: c.imageUrl,
      audioUrl: hasAudio ? c.audioUrl : null,
      spokenText: hasAudio ? null : c.spokenText,
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
