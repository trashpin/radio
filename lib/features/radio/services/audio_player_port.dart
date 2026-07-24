import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// The narrow audio-output contract the Radio Engine's adapter drives.
///
/// WHY THIS EXISTS: it keeps the ONE dependency on a concrete audio package
/// (`just_audio`) behind an interface, so the engine/adapter stay testable
/// (via a fake port) and the player can be swapped (e.g. for an `audio_service`
/// background handler) without touching the decision logic. [completions] fires
/// when the current item finishes, which the adapter uses to advance the engine.
abstract class AudioPlayerPort {
  Future<void> play(String url);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setVolume(double volume);

  /// Emits once each time the current item plays to completion.
  Stream<void> get completions;

  Future<void> dispose();
}

/// Production [AudioPlayerPort] backed by `just_audio`.
///
/// Translates completion of the underlying player into [completions]. Real
/// playback of `AudioSegment.audioUrl` happens here; everything above stays
/// audio-package-agnostic.
class JustAudioPlayerPort implements AudioPlayerPort {
  JustAudioPlayerPort([AudioPlayer? player]) : _player = player ?? AudioPlayer() {
    _stateSub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _completions.add(null);
    });
  }

  final AudioPlayer _player;
  final StreamController<void> _completions = StreamController<void>.broadcast();
  StreamSubscription<ProcessingState>? _stateSub;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> play(String url) async {
    await _player.setUrl(url);
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _player.dispose();
    await _completions.close();
  }
}
