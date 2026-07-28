import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';

/// The kinds of environmental content the Background Discovery Engine can teach,
/// listed in the priority order it prefers them (the first category with a
/// relevant, not-recently-played item nearby wins).
enum DiscoveryCategory {
  wildlife,
  plants,
  birds,
  trees,
  geology,
  history,
  interestingFact,
  hiddenGem;

  String get label {
    switch (this) {
      case DiscoveryCategory.wildlife:
        return 'Wildlife';
      case DiscoveryCategory.plants:
        return 'Plants';
      case DiscoveryCategory.birds:
        return 'Birds';
      case DiscoveryCategory.trees:
        return 'Trees';
      case DiscoveryCategory.geology:
        return 'Geology';
      case DiscoveryCategory.history:
        return 'History';
      case DiscoveryCategory.interestingFact:
        return 'Interesting fact';
      case DiscoveryCategory.hiddenGem:
        return 'Hidden gem';
    }
  }
}

/// One nearby thing the engine could talk about, normalized from any content
/// source (species, destination narration, map POIs, knowledge base, …).
class DiscoveryCandidate {
  const DiscoveryCandidate({
    required this.id,
    required this.category,
    required this.title,
    required this.distanceMeters,
    this.audioUrl,
    this.spokenText,
    this.parkId,
  });

  final String id;
  final DiscoveryCategory category;
  final String title;

  /// Distance from the traveler, meters.
  final double distanceMeters;

  /// Pre-recorded narration audio (preferred when present).
  final String? audioUrl;

  /// Fallback text spoken via on-device TTS when there is no recorded audio —
  /// so the radio can still teach something even before audio is generated.
  final String? spokenText;

  final String? parkId;

  bool get isPlayable =>
      (audioUrl != null && audioUrl!.trim().isNotEmpty) ||
      (spokenText != null && spokenText!.trim().isNotEmpty);
}

/// Maps a free-form content category/subcategory/name to a [DiscoveryCategory],
/// or null when it isn't an environmental topic worth teaching. Ordered so
/// narrower categories win over broader ones (birds before wildlife, trees
/// before plants).
DiscoveryCategory? discoveryCategoryFor(
  String? category, {
  String? subcategory,
  String? name,
}) {
  final text = [category, subcategory, name]
      .whereType<String>()
      .map((s) => s.toLowerCase())
      .join(' ');
  if (text.trim().isEmpty) return null;

  bool has(List<String> tokens) => tokens.any(text.contains);

  // Birds first (a subset of wildlife).
  if (has([
    'bird',
    'avian',
    'raptor',
    'owl',
    'eagle',
    'hawk',
    'heron',
    'egret',
    'woodpecker',
    'songbird',
    'waterfowl',
    'osprey',
  ])) {
    return DiscoveryCategory.birds;
  }
  // Trees before the broader plants group.
  if (has([
    'tree',
    ' oak',
    'pine',
    'cypress',
    'maple',
    'palm',
    'canopy',
    'hardwood',
    'sapling',
  ])) {
    return DiscoveryCategory.trees;
  }
  if (has([
    'plant',
    'flora',
    'wildflower',
    'flower',
    'fern',
    'shrub',
    'grass',
    'botan',
    'vegetation',
    'moss',
    'lichen',
    'orchid',
  ])) {
    return DiscoveryCategory.plants;
  }
  if (has([
    'wildlife',
    'animal',
    'mammal',
    'deer',
    'bear',
    'gator',
    'alligator',
    'reptile',
    'snake',
    'turtle',
    'fish',
    'amphibian',
    'fauna',
    'manatee',
    'fox',
    'bobcat',
    'otter',
  ])) {
    return DiscoveryCategory.wildlife;
  }
  if (has([
    'geolog',
    'rock',
    'spring',
    'sinkhole',
    'cave',
    'karst',
    'mineral',
    'formation',
    'limestone',
    'fossil',
    'dune',
    'aquifer',
  ])) {
    return DiscoveryCategory.geology;
  }
  if (has([
    'histor',
    'heritage',
    'settler',
    'pioneer',
    'battle',
    'fort',
    'ruin',
    'homestead',
    'cemetery',
    'cultural',
    'archae',
    'monument',
  ])) {
    return DiscoveryCategory.history;
  }
  if (has([
    'hidden',
    'gem',
    'secret',
    'overlook',
    'scenic',
    'vista',
    'viewpoint',
    'photo',
  ])) {
    return DiscoveryCategory.hiddenGem;
  }
  if (has(['fact', 'trivia', 'did you know', 'interesting'])) {
    return DiscoveryCategory.interestingFact;
  }
  return null;
}

/// Background Discovery Engine.
///
/// The radio doesn't only react to major destinations. When there hasn't been a
/// narration for a while (a run of songs with no spoken content), this engine
/// looks for nearby environmental content — in priority order: Wildlife,
/// Plants, Birds, Trees, Geology, History, Interesting facts, Hidden gems — and,
/// if something relevant is close by and hasn't been played recently, hands the
/// engine a narration segment to slip in between songs.
///
/// That way, even on a long scenic drive without a major attraction, the radio
/// keeps teaching you about the environment you're traveling through.
///
/// Pure and synchronous (no I/O): the runtime feeds it nearby content via
/// [updateNearby] and asks [due] between songs. Fully unit-testable.
class BackgroundDiscoveryScheduler {
  BackgroundDiscoveryScheduler({
    this.enabled = true,
    this.quietGapSongs = 3,
    this.radiusMeters = 1609,
    this.cooldownPlays = 8,
  });

  /// Master on/off.
  bool enabled;

  /// How many consecutive songs without a narration count as "a while" before
  /// the engine looks for something to teach.
  int quietGapSongs;

  /// Only consider content within this radius (default ~1 mile).
  double radiusMeters;

  /// A discovery item won't be repeated until this many other discovery items
  /// have played ("hasn't been played recently").
  int cooldownPlays;

  List<DiscoveryCandidate> _nearby = const [];
  int _songsSinceNarration = 0;
  int _playIndex = 0;
  final Map<String, int> _lastPlayedAt = {};

  /// Current nearby content pool (refreshed as the traveler moves).
  List<DiscoveryCandidate> get nearby => List.unmodifiable(_nearby);

  int get songsSinceNarration => _songsSinceNarration;

  /// True once it's been quiet long enough to consider a discovery insert.
  bool get isQuiet => _songsSinceNarration >= quietGapSongs;

  /// Replaces the nearby content pool (called by the runtime as GPS updates).
  void updateNearby(List<DiscoveryCandidate> candidates) {
    _nearby = List.of(candidates);
  }

  /// Records that a music track just played (advances the quiet-gap counter).
  void tick() => _songsSinceNarration++;

  /// Resets the quiet gap because a narration/story just played — discovery
  /// only fills genuine gaps, never stacks on top of other spoken content.
  void notifyNarration() => _songsSinceNarration = 0;

  /// Returns a narration segment to insert between songs when it's been quiet
  /// and a relevant, not-recently-played item is nearby; otherwise null.
  ///
  /// On a hit it advances the anti-repeat bookkeeping and resets the quiet gap.
  AudioSegment? due() {
    if (!enabled) return null;
    if (_songsSinceNarration < quietGapSongs) return null;
    final pick = select();
    if (pick == null) return null;

    _playIndex++;
    _lastPlayedAt[pick.id] = _playIndex;
    _songsSinceNarration = 0;
    return _toSegment(pick);
  }

  /// The candidate the engine would pick right now (nearest eligible item in the
  /// highest-priority category), or null. Exposed for tests/telemetry; does not
  /// mutate state.
  DiscoveryCandidate? select() {
    for (final category in DiscoveryCategory.values) {
      final inCat = _nearby
          .where((c) =>
              c.category == category &&
              c.isPlayable &&
              c.distanceMeters <= radiusMeters &&
              !recentlyPlayed(c.id))
          .toList()
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      if (inCat.isNotEmpty) return inCat.first;
    }
    return null;
  }

  /// Whether [id] has played within the recent cooldown window.
  bool recentlyPlayed(String id) {
    final at = _lastPlayedAt[id];
    if (at == null) return false;
    return (_playIndex - at) < cooldownPlays;
  }

  /// Clears all state (new trip).
  void reset() {
    _songsSinceNarration = 0;
    _playIndex = 0;
    _lastPlayedAt.clear();
  }

  AudioSegment _toSegment(DiscoveryCandidate c) {
    final hasAudio = c.audioUrl != null && c.audioUrl!.trim().isNotEmpty;
    return AudioSegment(
      id: 'discovery:${c.category.name}:${c.id}:'
          '${DateTime.now().microsecondsSinceEpoch}',
      title: c.title.isEmpty ? c.category.label : c.title,
      type: AudioSegmentType.narration,
      priority: PlaybackPriority.scheduledAnnouncement,
      audioUrl: hasAudio ? c.audioUrl : null,
      spokenText: hasAudio ? null : (c.spokenText ?? c.title),
      parkId: c.parkId,
      tags: [c.category.name],
      // Slots in after a song like a story; not an interruption over music.
      interruptible: false,
      resumeAfter: false,
    );
  }
}
