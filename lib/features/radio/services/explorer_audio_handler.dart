import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// The `audio_service` background handler for Explorer Radio.
///
/// WHY THIS EXISTS: to play audio in the background with OS media controls
/// (lock screen / notification / Bluetooth) and to provide the foundation for
/// Android Auto & Apple CarPlay. It wraps a `just_audio` player and is the ONLY
/// bridge between the OS media session and the Radio Engine.
///
/// IMPORTANT — two control paths, kept separate to avoid feedback loops:
///  • OS-initiated controls (lock-screen buttons) arrive via the overridden
///    [play]/[pause]/[stop]/[skipToNext]/[skipToPrevious] and are forwarded to
///    the ENGINE through the `on*` callbacks (the engine then decides + emits
///    events that drive playback).
///  • Programmatic control (from the engine's audio adapter) uses the internal
///    [playUrl]/[resumeAudio]/[pauseAudio]/[stopAudio], which touch ONLY the
///    player and never call back into the engine.
class ExplorerAudioHandler extends BaseAudioHandler {
  ExplorerAudioHandler([AudioPlayer? player])
      : _player = player ?? AudioPlayer() {
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _completions.add(null);
    });
    _player.playbackEventStream.listen((_) => _broadcastState());
  }

  final AudioPlayer _player;
  final StreamController<void> _completions = StreamController<void>.broadcast();

  /// Emits when the current item finishes (drives engine advance).
  Stream<void> get completions => _completions.stream;

  // Wired to the engine during init (OS controls → engine).
  VoidCallback? onPlayRequested;
  VoidCallback? onPauseRequested;
  VoidCallback? onStopRequested;
  VoidCallback? onSkipToNext;
  VoidCallback? onSkipToPrevious;

  // --- Programmatic control (from the engine adapter; no engine callbacks) ---

  Future<void> playUrl(String url, {MediaItem? item}) async {
    if (item != null) mediaItem.add(item);
    await _player.setUrl(url);
    await _player.play();
  }

  Future<void> resumeAudio() => _player.play();
  Future<void> pauseAudio() => _player.pause();
  Future<void> stopAudio() => _player.stop();
  Future<void> setVolumeLevel(double volume) => _player.setVolume(volume);

  // --- OS-initiated controls (lock screen / Auto / CarPlay) → engine ---------

  @override
  Future<void> play() async => onPlayRequested?.call();

  @override
  Future<void> pause() async => onPauseRequested?.call();

  @override
  Future<void> stop() async {
    onStopRequested?.call();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => onSkipToNext?.call();

  @override
  Future<void> skipToPrevious() async => onSkipToPrevious?.call();

  void _broadcastState() {
    const processingStates = {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    };
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      processingState:
          processingStates[_player.processingState] ?? AudioProcessingState.idle,
      playing: _player.playing,
      updatePosition: _player.position,
    ));
  }

  Future<void> disposeHandler() async {
    await _completions.close();
    await _player.dispose();
  }
}
