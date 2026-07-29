import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'package:explorer_os_mobile/features/radio/events/radio_event.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/services/audio_player_port.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';

/// Speaks DJ banter (dynamically generated text with no pre-recorded clip).
/// Abstracted so the default [TtsSpeaker] uses `flutter_tts` while tests inject
/// a fake without touching platform channels.
abstract class Speaker {
  /// Called when speech finishes (or errors) so the engine can advance.
  set onComplete(void Function() cb);
  Future<void> speak(String text);
  Future<void> pause();
  Future<void> stop();
}

/// Default [Speaker] backed by `flutter_tts`. The `FlutterTts` object is created
/// lazily on first use — constructing it touches a platform channel, so nothing
/// happens until the DJ actually talks.
class TtsSpeaker implements Speaker {
  FlutterTts? _tts;
  void Function()? _onComplete;

  FlutterTts _ensure() {
    final existing = _tts;
    if (existing != null) return existing;
    final t = FlutterTts();
    t.setCompletionHandler(() => _onComplete?.call());
    t.setErrorHandler((_) => _onComplete?.call());
    _tts = t;
    return t;
  }

  @override
  set onComplete(void Function() cb) => _onComplete = cb;

  @override
  Future<void> speak(String text) async {
    final tts = _ensure();
    await tts.setSpeechRate(0.5);
    await tts.speak(text);
  }

  @override
  Future<void> pause() async => _tts?.pause();

  @override
  Future<void> stop() async => _tts?.stop();
}

/// The bridge that turns the Radio Engine's playback INTENT into real audio.
///
/// WHY THIS EXISTS: the engine decides and emits `RadioEvent`s but produces no
/// sound. This adapter is the only place that connects those decisions to an
/// [AudioPlayerPort]:
///   • `SegmentStarted` with an `audioUrl` → play it
///   • `SegmentStarted` with `spokenText` (DJ banter) → speak it via [Speaker]
///   • `PlaybackPaused/Resumed/Stopped` → pause/resume/stop
///   • `VolumeChanged`/`MuteChanged` → set the player volume
/// and, crucially, when the player (or speaker) reports the item finished it
/// calls [RadioEngineService.onSegmentCompleted] — closing the loop so the
/// engine picks the next segment. Fully testable by injecting a fake port +
/// fake speaker.
class RadioAudioService {
  RadioAudioService({
    required this.engine,
    required this.port,
    Speaker? speaker,
  }) : _speaker = speaker ?? TtsSpeaker() {
    _speaker.onComplete = _finishSpeaking;
  }

  final RadioEngineService engine;
  final AudioPlayerPort port;
  final Speaker _speaker;

  StreamSubscription<RadioEvent>? _eventSub;
  StreamSubscription<void>? _completionSub;
  bool _speaking = false;
  Timer? _speakFallback;

  /// Position of the music that a temporary interruption displaced, so it can
  /// resume from the exact spot (never restarting the song).
  Duration? _pausedMusicPosition;
  bool _seekOnNextStart = false;

  /// Begins driving audio from the engine's events.
  void attach() {
    _eventSub = engine.events.listen(_onEvent);
    _completionSub =
        port.completions.listen((_) => engine.onSegmentCompleted());
  }

  Future<void> _onEvent(RadioEvent event) async {
    switch (event) {
      case SegmentStarted(:final segment):
        // Dynamically-generated DJ banter: speak it (no pre-recorded clip),
        // then advance the engine when the speech ends.
        final text = segment.spokenText;
        if (text != null && text.trim().isNotEmpty) {
          await _speak(text);
          return;
        }
        final url = segment.audioUrl;
        // Segments without a resolvable URL (not yet downloaded/authored) are
        // skipped here; a real deployment supplies URLs (or offline paths).
        if (url != null && url.isNotEmpty) {
          await port.play(url);
          // Resuming music after an interruption: continue from the exact spot
          // it paused at (never restart the song). Only the resumed MUSIC
          // segment is seeked — queued narrations in between are left alone.
          if (_seekOnNextStart &&
              _pausedMusicPosition != null &&
              segment.type == AudioSegmentType.music) {
            await port.seek(_pausedMusicPosition!);
            _seekOnNextStart = false;
            _pausedMusicPosition = null;
          }
        }
      case SegmentInterrupted(:final segment):
        // Capture where the displaced music was, synchronously, before the
        // interruption swaps the audio source.
        if (segment.type == AudioSegmentType.music) {
          _pausedMusicPosition = port.position;
        }
      case MusicResumed():
        // Arm the seek so the upcoming resumed-music SegmentStarted continues
        // from the saved position.
        _seekOnNextStart = _pausedMusicPosition != null;
      case PlaybackPaused():
        if (_speaking) await _speaker.pause();
        await port.pause();
      case PlaybackResumed():
        await port.resume();
      case PlaybackStopped():
        if (_speaking) await _speaker.stop();
        _speaking = false;
        await port.stop();
      case VolumeChanged(:final volume):
        await port.setVolume(volume);
      case MuteChanged(:final muted):
        await port.setVolume(muted ? 0 : engine.audioFocus.volume);
      case SegmentCompleted():
      case StationChanged():
      case QueueCleared():
        break;
    }
  }

  /// Speaks [text]. A fallback timer guards against web TTS not firing its
  /// completion handler, so the broadcast never stalls.
  Future<void> _speak(String text) async {
    _speakFallback?.cancel();
    _speaking = true;
    // ~2 words/sec speaking rate → a safe upper bound to auto-advance.
    final words = text.split(RegExp(r'\s+')).length;
    final secs = (words / 2.0).clamp(4, 60).toInt() + 4;
    _speakFallback = Timer(Duration(seconds: secs), _finishSpeaking);
    try {
      await _speaker.speak(text);
    } catch (_) {
      _finishSpeaking();
    }
  }

  void _finishSpeaking() {
    if (!_speaking) return;
    _speaking = false;
    _speakFallback?.cancel();
    _speakFallback = null;
    engine.onSegmentCompleted();
  }

  Future<void> detach() async {
    await _eventSub?.cancel();
    await _completionSub?.cancel();
    _speakFallback?.cancel();
    _eventSub = null;
    _completionSub = null;
  }

  Future<void> dispose() async {
    await detach();
    try {
      await _speaker.stop();
    } catch (_) {}
    await port.dispose();
  }
}
