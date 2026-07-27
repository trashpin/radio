import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// The narrow audio-output contract the [PlaybackManager] drives.
///
/// WHY THIS EXISTS: it keeps the ONE dependency on a concrete audio package
/// (`just_audio`) behind an interface so the engine stays fully unit-testable
/// (via a fake output) and the player can be swapped later (e.g. for an
/// `audio_service` background handler) without touching the queue/priority/state
/// logic. [completions] fires once each time the current item plays to
/// completion, which the manager uses to advance the queue / resume music.
///
/// The manager uses TWO of these — one for the music channel and one for the
/// narration channel — so music can be ducked and resumed around a narration.
abstract class AudioOutput {
  Future<void> play(String url);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setVolume(double volume);

  /// Emits once each time the current item plays to completion.
  Stream<void> get completions;

  Future<void> dispose();
}

/// Production [AudioOutput] backed by `just_audio`.
class JustAudioOutput implements AudioOutput {
  JustAudioOutput([AudioPlayer? player])
      : _player = player ?? AudioPlayer() {
    _stateSub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _completions.add(null);
    });
  }

  final AudioPlayer _player;
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  StreamSubscription<ProcessingState>? _stateSub;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> play(String url) async {
    // On web, calling setUrl while the player is actively playing does NOT
    // reliably switch the underlying <audio> source — it keeps playing the
    // previous track. Stopping first forces the element to release the old
    // source and load the new one, so interruptions actually swap the audio.
    await _player.stop();
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
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _player.dispose();
    await _completions.close();
  }
}
