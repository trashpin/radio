import 'package:audio_service/audio_service.dart';

import 'package:explorer_os_mobile/features/radio/services/audio_player_port.dart';
import 'package:explorer_os_mobile/features/radio/services/explorer_audio_handler.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';

/// An [AudioPlayerPort] backed by the `audio_service` background handler.
///
/// WHY THIS EXISTS: it's the drop-in replacement for `JustAudioPlayerPort` that
/// adds background playback + OS media controls, WITHOUT changing the engine or
/// its adapter — proving the value of the port seam. Programmatic calls route to
/// the handler's internal (no-callback) methods; OS controls flow the other way
/// via the handler's callbacks (wired in [RadioBackgroundAudio.init]).
class AudioServicePlayerPort implements AudioPlayerPort {
  const AudioServicePlayerPort(this._handler);

  final ExplorerAudioHandler _handler;

  @override
  Stream<void> get completions => _handler.completions;

  @override
  Future<void> play(String url) => _handler.playUrl(url);

  @override
  Future<void> pause() => _handler.pauseAudio();

  @override
  Future<void> resume() => _handler.resumeAudio();

  @override
  Future<void> stop() => _handler.stopAudio();

  @override
  Future<void> setVolume(double volume) => _handler.setVolumeLevel(volume);

  @override
  Future<void> dispose() => _handler.disposeHandler();
}

/// Bootstraps background audio (call ONCE from `main` on mobile before running
/// the app).
///
/// Not called by default (so web/tests never touch platform audio focus). It
/// initializes `audio_service`, wires OS controls to the engine, and returns a
/// port you override `audioPlayerPortProvider` with.
class RadioBackgroundAudio {
  const RadioBackgroundAudio._();

  static Future<AudioServicePlayerPort> init(RadioEngineService engine) async {
    final handler = await AudioService.init(
      builder: ExplorerAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.exploreros.audio',
        androidNotificationChannelName: 'ExplorerOS Radio',
        androidNotificationOngoing: true,
      ),
    );
    handler
      ..onPlayRequested = engine.play
      ..onPauseRequested = engine.pause
      ..onStopRequested = engine.stop
      ..onSkipToNext = engine.skip
      ..onSkipToPrevious = engine.previous;
    return AudioServicePlayerPort(handler);
  }
}
