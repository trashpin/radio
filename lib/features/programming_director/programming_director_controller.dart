import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/audio_recall/audio_recall.dart';
import 'package:explorer_os_mobile/features/admin/audio_recall/audio_recall_repository.dart';
import 'package:explorer_os_mobile/features/playback/playback_manager.dart';
import 'package:explorer_os_mobile/features/playback/playback_models.dart';
import 'package:explorer_os_mobile/features/playback/playback_providers.dart';
import 'package:explorer_os_mobile/features/programming_director/programming_director.dart';

/// Maps a unified-inventory item to the programming slot it can fill.
ProgrammingSlotType? slotForInventory(AudioInventoryItem i) {
  if (!i.hasFile) return null;
  final cat = (i.category ?? '').toLowerCase();
  switch (i.source) {
    case AudioSource.songs:
      return ProgrammingSlotType.song;
    case AudioSource.djBanter:
      return ProgrammingSlotType.djWelcome;
    case AudioSource.radioSegment:
      if (cat.contains('station')) return ProgrammingSlotType.stationId;
      if (cat.contains('intro')) return ProgrammingSlotType.songIntro;
      if (cat.contains('outro')) return ProgrammingSlotType.songOutro;
      if (cat.contains('promo')) return ProgrammingSlotType.promo;
      if (cat.contains('safety')) return ProgrammingSlotType.safety;
      if (cat.contains('wildlife')) return ProgrammingSlotType.wildlife;
      return ProgrammingSlotType.stationId;
    case AudioSource.story:
      return ProgrammingSlotType.story;
    case AudioSource.narration:
    case AudioSource.audioAssets:
    case AudioSource.media:
      if (cat.contains('arrival') || cat.contains('welcome')) {
        return ProgrammingSlotType.arrival;
      }
      if (cat.contains('depart')) return ProgrammingSlotType.departure;
      if (cat.contains('history') || cat.contains('historic')) {
        return ProgrammingSlotType.history;
      }
      if (cat.contains('safety')) return ProgrammingSlotType.safety;
      if (cat.contains('bird') ||
          cat.contains('wildlife') ||
          cat.contains('mammal') ||
          cat.contains('reptile') ||
          cat.contains('fish')) {
        return ProgrammingSlotType.wildlife;
      }
      return ProgrammingSlotType.interestingFact;
  }
}

/// Builds the per-slot asset pools from the unified inventory (reuse existing).
Map<ProgrammingSlotType, List<ProgrammingAsset>> buildProgrammingPools(
    List<AudioInventoryItem> items) {
  final pools = <ProgrammingSlotType, List<ProgrammingAsset>>{};
  for (final i in items) {
    final slot = slotForInventory(i);
    if (slot == null) continue;
    final asset = ProgrammingAsset(
      id: i.id,
      title: i.displayTitle,
      audioUrl: i.publicUrl!,
      slotType: slot,
      source: i.source.name,
    );
    pools.putIfAbsent(slot, () => []).add(asset);
    // Songs also seed the generic music pool (for gap-fill).
    if (slot == ProgrammingSlotType.song) {
      pools.putIfAbsent(ProgrammingSlotType.music, () => []).add(asset);
    }
    // History tease reuses history content.
    if (slot == ProgrammingSlotType.history) {
      pools.putIfAbsent(ProgrammingSlotType.historyTease, () => []).add(asset);
    }
  }
  return pools;
}

class ProgrammingSnapshot {
  const ProgrammingSnapshot({
    this.running = false,
    this.position = 0,
    this.nowPlaying,
    this.upNext,
    this.log = const [],
    this.playedCount = 0,
    this.poolCounts = const {},
  });

  final bool running;
  final int position;
  final ProgrammingResult? nowPlaying;
  final String? upNext;
  final List<String> log;
  final int playedCount;
  final Map<ProgrammingSlotType, int> poolCounts;

  ProgrammingSnapshot copyWith({
    bool? running,
    int? position,
    ProgrammingResult? nowPlaying,
    String? upNext,
    List<String>? log,
    int? playedCount,
    Map<ProgrammingSlotType, int>? poolCounts,
  }) =>
      ProgrammingSnapshot(
        running: running ?? this.running,
        position: position ?? this.position,
        nowPlaying: nowPlaying ?? this.nowPlaying,
        upNext: upNext ?? this.upNext,
        log: log ?? this.log,
        playedCount: playedCount ?? this.playedCount,
        poolCounts: poolCounts ?? this.poolCounts,
      );
}

/// The Programming Director runtime: schedules the station clock over the
/// unified inventory and enacts each slot on the Playback Manager. Reuses
/// existing assets only; never generates.
final programmingDirectorControllerProvider =
    NotifierProvider<ProgrammingDirectorController, ProgrammingSnapshot>(
        ProgrammingDirectorController.new);

class ProgrammingDirectorController extends Notifier<ProgrammingSnapshot> {
  static const _engine = ProgrammingDirector();
  static const _clock = ProgrammingClock.station;

  Timer? _timer;
  int _position = 0;
  final Set<String> _played = {};
  final List<String> _log = [];

  /// Preview cadence: how long each item airs before the clock advances so the
  /// rotation is observable. (Production would advance on real completion.)
  Duration slotDuration = const Duration(seconds: 5);

  PlaybackManager get _pm => ref.read(playbackManagerProvider);

  @override
  ProgrammingSnapshot build() {
    ref.onDispose(() => _timer?.cancel());
    return const ProgrammingSnapshot();
  }

  Map<ProgrammingSlotType, List<ProgrammingAsset>> _pools() =>
      buildProgrammingPools(ref.read(audioInventoryProvider).value ?? const []);

  Future<void> togglePlay() => state.running ? stop() : start();

  Future<void> start() async {
    if (state.running) return;
    state = state.copyWith(running: true);
    _step();
    _timer?.cancel();
    _timer = Timer.periodic(slotDuration, (_) => _step());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _pm.pauseMusic();
    await _pm.cancelNarration();
    state = state.copyWith(running: false);
  }

  Future<void> skip() async {
    _appendLog('⏭ skipped');
    _step();
  }

  void _step() {
    final pools = _pools();
    final result = _engine.next(ProgrammingContext(
      clock: _clock,
      position: _position,
      pools: pools,
      playedKeys: _played,
    ));
    _position = result.nextPosition;

    if (result.hasAsset) {
      final a = result.asset!;
      _played.add(a.key);
      _enact(a);
      _appendLog('▶ $result');
      // Record the play against the canonical index.
      if (a.source == AudioSource.audioAssets.name) {
        ref.read(audioRecallRepositoryProvider)
            .recordPlay(a.id, usedBy: 'programming_director');
      }
    } else {
      _appendLog('… ${result.reason}');
    }

    // Peek up-next (non-mutating).
    final peek = _engine.next(ProgrammingContext(
      clock: _clock,
      position: _position,
      pools: pools,
      playedKeys: _played,
    ));

    final counts = {
      for (final e in pools.entries) e.key: e.value.length,
    };
    state = state.copyWith(
      position: _position,
      nowPlaying: result,
      upNext: peek.hasAsset ? peek.toString() : null,
      log: List.unmodifiable(_log),
      playedCount: _played.length,
      poolCounts: counts,
    );
  }

  void _enact(ProgrammingAsset a) {
    final item = PlaybackItem(
      type: a.slotType.isMusic ? PlaybackItemType.music : PlaybackItemType.poi,
      title: a.title,
      audioUrl: a.audioUrl,
      metadata: {'slot': a.slotType.name, 'source': a.source ?? ''},
    );
    if (a.slotType.isMusic) {
      _pm.playMusic(item);
    } else {
      _pm.playNarration(item);
    }
  }

  void _appendLog(String line) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    _log.insert(0, '$t  $line');
    if (_log.length > 40) _log.removeLast();
  }
}
