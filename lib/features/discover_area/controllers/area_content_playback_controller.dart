import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:explorer_os_mobile/features/discover_area/models/area_content_block.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/events/radio_event.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';

/// State of an area-content sequence (History/Nature/Geology, etc.) playing
/// on the ExplorerOS Radio engine.
class AreaContentPlaybackState {
  const AreaContentPlaybackState({
    this.blocks = const [],
    this.index = 0,
    this.playing = false,
  });

  final List<AreaContentBlock> blocks;
  final int index;
  final bool playing;

  AreaContentBlock? get current =>
      index >= 0 && index < blocks.length ? blocks[index] : null;
  bool get hasNext => index + 1 < blocks.length;
  bool get active => blocks.isNotEmpty;

  AreaContentPlaybackState copyWith({int? index, bool? playing}) =>
      AreaContentPlaybackState(
        blocks: blocks,
        index: index ?? this.index,
        playing: playing ?? this.playing,
      );
}

/// Plays a sequence of [AreaContentBlock]s through the SAME audio engine used
/// everywhere else in the app (gems, communities, GPS triggers) — recorded
/// audio when a block has it, on-device TTS otherwise — auto-advancing to the
/// next block when one finishes, exactly the way [GemNarrationController]
/// handles a single gem, extended to a sequence.
class AreaContentPlaybackController extends Notifier<AreaContentPlaybackState> {
  final FlutterTts _tts = FlutterTts();
  bool _wired = false;
  bool _wasPlaying = false;
  String? _segId;
  Timer? _fallback;
  StreamSubscription<RadioEvent>? _events;

  @override
  AreaContentPlaybackState build() {
    ref.onDispose(() {
      _events?.cancel();
      _fallback?.cancel();
    });
    return const AreaContentPlaybackState();
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

  /// Starts (or restarts) playing [blocks] from the beginning.
  Future<void> play(List<AreaContentBlock> blocks) async {
    _wire();
    _fallback?.cancel();
    try {
      await _tts.stop();
    } catch (_) {}
    state = AreaContentPlaybackState(blocks: blocks, index: 0, playing: true);
    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    final block = state.current;
    if (block == null) {
      state = state.copyWith(playing: false);
      return;
    }
    if (block.hasAudio) {
      _segId = 'area-content:${block.id}:${DateTime.now().millisecondsSinceEpoch}';
      final radio = ref.read(radioEngineControllerProvider.notifier);
      radio.requestInterruption(
        AudioSegment(
          id: _segId!,
          title: block.title,
          type: AudioSegmentType.narration,
          priority: PlaybackPriority.scheduledAnnouncement,
          audioUrl: block.audioUrl,
          interruptible: true,
          resumeAfter: true,
        ),
      );
      if (ref.read(radioEngineControllerProvider).status != PlaybackStatus.playing) {
        radio.play();
      }
    } else if (block.hasNarration) {
      await _speak(block.narrationScript!);
    } else {
      // Nothing to say for this block — move straight on.
      _advance();
    }
  }

  Future<void> _speak(String script) async {
    final controller = ref.read(radioEngineControllerProvider.notifier);
    _wasPlaying =
        ref.read(radioEngineControllerProvider).status == PlaybackStatus.playing;
    if (_wasPlaying) controller.pause();
    final secs = (script.split(RegExp(r'\s+')).length / 2.6).round().clamp(6, 240);
    _fallback = Timer(Duration(seconds: secs), _finishSpokenBlock);
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      await _tts.speak(script);
    } catch (_) {}
  }

  void _finishSpokenBlock() {
    _fallback?.cancel();
    _fallback = null;
    if (_wasPlaying) {
      try {
        ref.read(radioEngineControllerProvider.notifier).resume();
      } catch (_) {}
      _wasPlaying = false;
    }
    _advance();
  }

  void _advance() {
    if (!state.hasNext) {
      state = state.copyWith(playing: false);
      return;
    }
    state = state.copyWith(index: state.index + 1);
    _playCurrent();
  }

  /// Skips ahead to the next block manually (e.g. a "Next" button).
  void skipToNext() {
    if (_segId != null) {
      _segId = null;
      try {
        ref.read(radioEngineControllerProvider.notifier).skip();
      } catch (_) {}
    } else {
      try {
        _tts.stop();
      } catch (_) {}
      _fallback?.cancel();
    }
    _advance();
  }

  /// Stops playback entirely and returns to the normal radio interface.
  Future<void> stop() async {
    if (_segId != null) {
      _segId = null;
      try {
        ref.read(radioEngineControllerProvider.notifier).skip();
      } catch (_) {}
    } else {
      try {
        await _tts.stop();
      } catch (_) {}
      _fallback?.cancel();
      if (_wasPlaying) {
        try {
          ref.read(radioEngineControllerProvider.notifier).resume();
        } catch (_) {}
        _wasPlaying = false;
      }
    }
    state = const AreaContentPlaybackState();
  }
}

final areaContentPlaybackControllerProvider = NotifierProvider<
    AreaContentPlaybackController, AreaContentPlaybackState>(
  AreaContentPlaybackController.new,
);
