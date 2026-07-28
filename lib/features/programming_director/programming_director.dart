/// The kinds of slots a radio "clock" (hour rotation) is built from.
enum ProgrammingSlotType {
  djWelcome,
  stationId,
  songIntro,
  song,
  songOutro,
  historyTease,
  history,
  arrival,
  departure,
  wildlife,
  safety,
  promo,
  guideTip,
  story,
  interestingFact,
  music;

  String get label => name
      .replaceAllMapped(RegExp('([A-Z])'), (m) => ' ${m[1]}')
      .replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase())
      .trim();

  bool get isMusic => this == ProgrammingSlotType.song || this == ProgrammingSlotType.music;
}

/// A resolved, playable asset for a slot (reused from an existing catalog — the
/// Programming Director never generates; it schedules what already exists).
class ProgrammingAsset {
  const ProgrammingAsset({
    required this.id,
    required this.title,
    required this.audioUrl,
    required this.slotType,
    this.source,
  });

  final String id;
  final String title;
  final String audioUrl;
  final ProgrammingSlotType slotType;
  final String? source;

  /// Anti-repeat key.
  String get key => '${source ?? slotType.name}:$id';
}

/// The station clock — an ordered rotation of slot types that repeats. Mirrors
/// the brief's example (DJ Welcome → Station ID → Song Intro → Song → …).
class ProgrammingClock {
  const ProgrammingClock(this.slots);

  final List<ProgrammingSlotType> slots;

  static const station = ProgrammingClock([
    ProgrammingSlotType.djWelcome,
    ProgrammingSlotType.stationId,
    ProgrammingSlotType.songIntro,
    ProgrammingSlotType.song,
    ProgrammingSlotType.songOutro,
    ProgrammingSlotType.historyTease,
    ProgrammingSlotType.song,
    ProgrammingSlotType.arrival,
    ProgrammingSlotType.history,
    ProgrammingSlotType.music,
    ProgrammingSlotType.wildlife,
    ProgrammingSlotType.stationId,
    ProgrammingSlotType.song,
  ]);
}

/// Inputs for the next scheduling decision.
class ProgrammingContext {
  const ProgrammingContext({
    required this.clock,
    required this.position,
    required this.pools,
    this.playedKeys = const {},
  });

  final ProgrammingClock clock;

  /// Current index into the clock.
  final int position;

  /// Available (already-existing) assets per slot type.
  final Map<ProgrammingSlotType, List<ProgrammingAsset>> pools;

  /// Keys already played (anti-repeat within the rotation).
  final Set<String> playedKeys;
}

/// The result of one scheduling step.
class ProgrammingResult {
  const ProgrammingResult({
    required this.nextPosition,
    this.asset,
    this.slotType,
    this.reason = '',
  });

  final int nextPosition;
  final ProgrammingAsset? asset;
  final ProgrammingSlotType? slotType;
  final String reason;

  bool get hasAsset => asset != null;

  @override
  String toString() => asset == null
      ? 'silent · $reason'
      : '${slotType?.label}: ${asset!.title}${reason.isNotEmpty ? ' · $reason' : ''}';
}

/// The Programming Director — a pure station-clock sequencer.
///
/// Walks the clock, picks the next EXISTING asset for the current slot (reuse,
/// with anti-repeat + recycle), skips empty slots, and falls back to music so
/// there is never dead air. It plays nothing itself — the runtime controller
/// enacts the result on the Playback Manager.
class ProgrammingDirector {
  const ProgrammingDirector();

  ProgrammingResult next(ProgrammingContext ctx) {
    final slots = ctx.clock.slots;
    if (slots.isEmpty) return const ProgrammingResult(nextPosition: 0, reason: 'no clock');

    for (var attempt = 0; attempt < slots.length; attempt++) {
      final pos = (ctx.position + attempt) % slots.length;
      final slot = slots[pos];
      final pool = ctx.pools[slot] ?? const [];
      if (pool.isEmpty) continue; // skip empty slot

      // Prefer an unplayed asset; if all played, recycle the first (round-robin).
      final fresh = pool.where((a) => !ctx.playedKeys.contains(a.key)).toList();
      final chosen = fresh.isNotEmpty ? fresh.first : pool.first;
      return ProgrammingResult(
        asset: chosen,
        slotType: slot,
        nextPosition: pos + 1,
        reason: fresh.isEmpty ? 'recycled' : 'fresh',
      );
    }

    // No slot had an asset → fill with music if any exists.
    final music = ctx.pools[ProgrammingSlotType.music] ??
        ctx.pools[ProgrammingSlotType.song] ??
        const [];
    if (music.isNotEmpty) {
      return ProgrammingResult(
        asset: music.first,
        slotType: ProgrammingSlotType.music,
        nextPosition: ctx.position + 1,
        reason: 'music fill',
      );
    }
    return ProgrammingResult(nextPosition: ctx.position + 1, reason: 'no assets');
  }
}
