import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';

/// MARION COUNTY EXPLORE's fixed programming order (spec section 5). Content
/// for each category is sourced from existing tables (see
/// `explore_providers.dart`) — this enum only orders the rotation.
enum ExploreCategory {
  whereHeaded,
  whereYouAre,
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
  });

  final String id;
  final ExploreCategory category;
  final String title;
  final String? audioUrl;
  final String? spokenText;
  final TellMeMoreContext? tellMeMoreContext;

  bool get isPlayable =>
      (audioUrl ?? '').trim().isNotEmpty || (spokenText ?? '').trim().isNotEmpty;
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
/// should play next. Rotates WHERE YOU'RE HEADED → WHERE YOU ARE → MARION
/// COUNTY → WILDLIFE → NATURE → GEOLOGY → HISTORY → repeat, skipping any
/// category with no usable content right now, and never repeating an item
/// until [cooldownPlays] other Explore items have aired. Returns null when
/// there is truly nothing to say anywhere — the caller falls back to normal
/// content/music, exactly like [BackgroundDiscoveryScheduler.due].
class ExploreRotationScheduler {
  ExploreRotationScheduler({this.cooldownPlays = 6});

  /// An Explore item won't repeat until this many other Explore items have
  /// played.
  int cooldownPlays;

  Map<ExploreCategory, List<ExploreCandidate>> _pool = const {};
  int _categoryCursor = 0;
  int _playIndex = 0;
  final Map<String, int> _lastPlayedAt = {};

  /// IDs already surfaced as an urgent interruption this trip — an urgent cue
  /// fires once, not on every tick while it stays close.
  final Set<String> _urgentFired = {};

  /// Replaces the candidate pool per category (runtime pushes as GPS/content
  /// change). Does not touch rotation position or play history.
  void updateCandidates(Map<ExploreCategory, List<ExploreCandidate>> pool) {
    _pool = pool;
  }

  bool recentlyPlayed(String id) {
    final at = _lastPlayedAt[id];
    if (at == null) return false;
    return (_playIndex - at) < cooldownPlays;
  }

  void _markPlayed(String id) {
    _playIndex++;
    _lastPlayedAt[id] = _playIndex;
  }

  /// The next rotation segment, in category order, continuing from wherever
  /// the cursor left off (spec section 7 — a location-priority interruption
  /// must not restart the whole rotation). Null when every category is
  /// either empty or fully on cooldown right now.
  AudioSegment? due() {
    final pick = select();
    if (pick == null) return null;
    _markPlayed(pick.id);
    // Resume the rotation from the NEXT category after this one next time.
    _categoryCursor =
        (ExploreCategory.values.indexOf(pick.category) + 1) %
            ExploreCategory.values.length;
    return _toSegment(pick, resumeAfter: true);
  }

  /// The candidate [due] would pick right now, without mutating any state —
  /// exposed for tests/telemetry.
  ExploreCandidate? select() {
    final categories = ExploreCategory.values;
    for (var i = 0; i < categories.length; i++) {
      final cat = categories[(_categoryCursor + i) % categories.length];
      final eligible = (_pool[cat] ?? const [])
          .where((c) => c.isPlayable && !recentlyPlayed(c.id))
          .toList();
      if (eligible.isNotEmpty) return eligible.first;
    }
    return null;
  }

  /// Checks whether an important location just became relevant enough to
  /// jump the queue (spec section 7). [candidate] is the current
  /// WHERE YOU'RE HEADED item, already resolved by the runtime;
  /// [isCloseEnough] is the runtime's own "worth interrupting for" test
  /// (e.g. under a mile, or a couple of minutes out) so this class stays
  /// free of GPS/ETA math. Fires at most once per candidate id per trip.
  AudioSegment? urgent(ExploreCandidate? candidate, {required bool isCloseEnough}) {
    if (candidate == null || !candidate.isPlayable || !isCloseEnough) return null;
    if (_urgentFired.contains(candidate.id)) return null;
    _urgentFired.add(candidate.id);
    _markPlayed(candidate.id);
    return _toSegment(candidate, resumeAfter: true, urgent: true);
  }

  /// New trip — clears rotation position, play history, and urgent memory.
  void reset() {
    _categoryCursor = 0;
    _playIndex = 0;
    _lastPlayedAt.clear();
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
      audioUrl: hasAudio ? c.audioUrl : null,
      spokenText: hasAudio ? null : c.spokenText,
      tags: ['explore', c.category.name],
      interruptible: false,
      resumeAfter: resumeAfter,
      tellMeMoreContext: c.tellMeMoreContext,
    );
  }
}
