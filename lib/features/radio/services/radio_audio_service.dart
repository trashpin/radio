import 'dart:async';

import 'package:explorer_os_mobile/features/radio/events/radio_event.dart';
import 'package:explorer_os_mobile/features/radio/services/audio_player_port.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';

/// The bridge that turns the Radio Engine's playback INTENT into real audio.
///
/// WHY THIS EXISTS: the engine decides and emits `RadioEvent`s but produces no
/// sound. This adapter is the only place that connects those decisions to an
/// [AudioPlayerPort]:
///   • `SegmentStarted` → play the segment's `audioUrl`
///   • `PlaybackPaused/Resumed/Stopped` → pause/resume/stop
///   • `VolumeChanged`/`MuteChanged` → set the player volume
/// and, crucially, when the player reports a track finished it calls
/// [RadioEngineService.onSegmentCompleted] — closing the loop so the engine
/// picks the next segment. Fully testable by injecting a fake port.
class RadioAudioService {
  RadioAudioService({required this.engine, required this.port});

  final RadioEngineService engine;
  final AudioPlayerPort port;

  StreamSubscription<RadioEvent>? _eventSub;
  StreamSubscription<void>? _completionSub;

  /// Begins driving audio from the engine's events.
  void attach() {
    _eventSub = engine.events.listen(_onEvent);
    _completionSub =
        port.completions.listen((_) => engine.onSegmentCompleted());
  }

  Future<void> _onEvent(RadioEvent event) async {
    switch (event) {
      case SegmentStarted(:final segment):
        final url = segment.audioUrl;
        // Segments without a resolvable URL (not yet downloaded/authored) are
        // skipped here; a real deployment supplies URLs (or offline paths).
        if (url != null && url.isNotEmpty) await port.play(url);
      case PlaybackPaused():
        await port.pause();
      case PlaybackResumed():
        await port.resume();
      case PlaybackStopped():
        await port.stop();
      case VolumeChanged(:final volume):
        await port.setVolume(volume);
      case MuteChanged(:final muted):
        await port.setVolume(muted ? 0 : engine.audioFocus.volume);
      case SegmentCompleted():
      case SegmentInterrupted():
      case MusicResumed():
      case StationChanged():
      case QueueCleared():
        break;
    }
  }

  Future<void> detach() async {
    await _eventSub?.cancel();
    await _completionSub?.cancel();
    _eventSub = null;
    _completionSub = null;
  }

  Future<void> dispose() async {
    await detach();
    await port.dispose();
  }
}
