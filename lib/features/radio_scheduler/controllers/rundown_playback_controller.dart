import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/events/radio_event.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';
import 'package:explorer_os_mobile/features/radio_scheduler/models/rundown.dart';

AudioSegmentType _segmentTypeFor(RundownItemType t) {
  switch (t) {
    case RundownItemType.music:
      return AudioSegmentType.music;
    case RundownItemType.stationId:
      return AudioSegmentType.stationIdentification;
    case RundownItemType.weather:
      return AudioSegmentType.weather;
    case RundownItemType.event:
      return AudioSegmentType.specialEvent;
    case RundownItemType.history:
    case RundownItemType.localFact:
    case RundownItemType.locationStory:
      return AudioSegmentType.narration;
    case RundownItemType.djBanter:
    case RundownItemType.sweeper:
    case RundownItemType.customAudio:
    case RundownItemType.silence:
      return AudioSegmentType.announcement;
  }
}

/// Converts a rundown item into a playable [AudioSegment], reusing the existing
/// engine. Returns null when the item can't be aired right now (silence — a
/// timed gap handled by the controller — or a non-silence item with neither
/// audio nor a script), so the player can SKIP it and continue.
AudioSegment? rundownItemToSegment(RundownItem item, {required String segId}) {
  if (item.type.isSilence) return null;
  final audio = item.hasAudio ? item.audioUrl : null;
  final text = (!item.hasAudio && item.hasScript) ? item.script : null;
  if (audio == null && text == null) return null;
  return AudioSegment(
    id: segId,
    title: item.displayName,
    type: _segmentTypeFor(item.type),
    priority: PlaybackPriority.scheduledAnnouncement,
    audioUrl: audio,
    spokenText: text,
    duration: Duration(seconds: item.effectiveSeconds),
    interruptible: true,
    resumeAfter: false,
  );
}

/// Now-playing + transport state for a rundown preview.
class RundownPlaybackState {
  const RundownPlaybackState({
    this.items = const [],
    this.index = -1,
    this.playing = false,
    this.paused = false,
    this.elapsedSeconds = 0,
  });

  /// The enabled items being aired, in order.
  final List<RundownItem> items;
  final int index;
  final bool playing;
  final bool paused;
  final int elapsedSeconds;

  RundownItem? get current =>
      index >= 0 && index < items.length ? items[index] : null;
  RundownItem? get next => index + 1 < items.length ? items[index + 1] : null;
  List<RundownItem> get upcoming =>
      index + 1 < items.length ? items.sublist(index + 1) : const [];
  bool get hasNext => index + 1 < items.length;
  bool get active => playing || paused;

  int get remainingSeconds {
    final c = current;
    if (c == null) return 0;
    final r = c.effectiveSeconds - elapsedSeconds;
    return r < 0 ? 0 : r;
  }

  RundownPlaybackState copyWith({
    List<RundownItem>? items,
    int? index,
    bool? playing,
    bool? paused,
    int? elapsedSeconds,
  }) =>
      RundownPlaybackState(
        items: items ?? this.items,
        index: index ?? this.index,
        playing: playing ?? this.playing,
        paused: paused ?? this.paused,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      );
}

/// Drives a rundown through the EXISTING audio engine (no new player): each
/// item becomes an [AudioSegment] played via the radio engine (or a TTS line,
/// or a timed silence), auto-advancing to the next when it completes. If an
/// item is unavailable or its audio fails to start, a per-item fallback timer
/// fires and the player skips to the next item so the rundown keeps going.
class RundownPlaybackController extends Notifier<RundownPlaybackState> {
  final FlutterTts _tts = FlutterTts();
  bool _wired = false;
  String? _segId;
  Timer? _fallback; // per-item safety net (skip-on-fail / silence gap)
  Timer? _ticker; // 1s elapsed counter for now-playing
  StreamSubscription<RadioEvent>? _events;

  @override
  RundownPlaybackState build() {
    ref.onDispose(() {
      _events?.cancel();
      _fallback?.cancel();
      _ticker?.cancel();
    });
    return const RundownPlaybackState();
  }

  void _wire() {
    if (_wired) return;
    _wired = true;
    _events = ref.read(radioEngineServiceProvider).events.listen((e) {
      if (_segId != null && e is SegmentCompleted && e.segment.id == _segId) {
        _segId = null;
        _advance();
      }
    });
  }

  /// Starts (or restarts) the rundown from [startIndex], airing only enabled
  /// items in order.
  Future<void> play(List<RundownItem> items, {int startIndex = 0}) async {
    _wire();
    final enabled = [for (final i in items) if (i.enabled) i];
    if (enabled.isEmpty) return;
    final idx = startIndex.clamp(0, enabled.length - 1);
    _resetTimers();
    await _stopTts();
    state = RundownPlaybackState(
        items: enabled, index: idx, playing: true, paused: false);
    _startTicker();
    await _playCurrent();
  }

  /// Starts from a specific item id (e.g. "Start from selected item").
  Future<void> startFromItem(List<RundownItem> items, String itemId) async {
    final enabled = [for (final i in items) if (i.enabled) i];
    final idx = enabled.indexWhere((i) => i.id == itemId);
    await play(items, startIndex: idx < 0 ? 0 : idx);
  }

  Future<void> _playCurrent() async {
    final item = state.current;
    if (item == null) {
      _finish();
      return;
    }
    state = state.copyWith(elapsedSeconds: 0);

    // Silence: a pure timed gap — no audio engine, just wait then advance.
    if (item.type.isSilence) {
      _segId = null;
      _fallback = Timer(Duration(seconds: item.effectiveSeconds), _advance);
      return;
    }

    final segId =
        'rundown:${item.id}:${DateTime.now().millisecondsSinceEpoch}';
    final segment = rundownItemToSegment(item, segId: segId);
    if (segment == null) {
      // Unavailable (no audio + no script) → skip and keep going.
      _advance();
      return;
    }

    if (segment.spokenText != null) {
      await _speak(segment.spokenText!, item.effectiveSeconds);
      return;
    }

    _segId = segId;
    final radio = ref.read(radioEngineControllerProvider.notifier);
    radio.requestInterruption(segment);
    if (ref.read(radioEngineControllerProvider).status !=
        PlaybackStatus.playing) {
      radio.play();
    }
    // Safety net: if completion never fires (bad/missing audio), skip after the
    // item's duration + a small grace so the rundown never stalls.
    _fallback = Timer(
      Duration(seconds: item.effectiveSeconds + 4),
      () {
        if (_segId == segId) {
          _segId = null;
          _advance();
        }
      },
    );
  }

  Future<void> _speak(String script, int seconds) async {
    _segId = null;
    _fallback = Timer(Duration(seconds: seconds), _advance);
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.45);
      await _tts.speak(script);
    } catch (_) {}
  }

  void _advance() {
    _fallback?.cancel();
    if (!state.hasNext) {
      _finish();
      return;
    }
    state = state.copyWith(index: state.index + 1, elapsedSeconds: 0);
    _playCurrent();
  }

  /// Manual skip to the next item.
  void skip() {
    _stopCurrentPlayback();
    _advance();
  }

  void pause() {
    if (!state.playing || state.paused) return;
    _ticker?.cancel();
    try {
      ref.read(radioEngineControllerProvider.notifier).pause();
    } catch (_) {}
    try {
      _tts.stop();
    } catch (_) {}
    state = state.copyWith(paused: true);
  }

  void resume() {
    if (!state.paused) return;
    try {
      ref.read(radioEngineControllerProvider.notifier).resume();
    } catch (_) {}
    state = state.copyWith(paused: false);
    _startTicker();
  }

  Future<void> stop() async {
    _stopCurrentPlayback();
    _resetTimers();
    state = const RundownPlaybackState();
  }

  void _stopCurrentPlayback() {
    if (_segId != null) {
      _segId = null;
      try {
        ref.read(radioEngineControllerProvider.notifier).skip();
      } catch (_) {}
    }
    try {
      _tts.stop();
    } catch (_) {}
    _fallback?.cancel();
  }

  void _finish() {
    _resetTimers();
    state = state.copyWith(playing: false, paused: false);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!state.playing || state.paused) return;
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
  }

  void _resetTimers() {
    _fallback?.cancel();
    _fallback = null;
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _stopTts() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

final rundownPlaybackControllerProvider =
    NotifierProvider<RundownPlaybackController, RundownPlaybackState>(
  RundownPlaybackController.new,
);
