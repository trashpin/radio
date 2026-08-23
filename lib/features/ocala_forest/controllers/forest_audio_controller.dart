import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';

/// ROOT CAUSE of "radio plays instead of forest information" (fixed here):
/// every forest narration call site used to route through the shared
/// `radioEngineControllerProvider` via `requestInterruption` + `play()`.
/// That engine is a PERPETUAL rotation service — its own
/// `RadioEngineService.onSegmentCompleted()` unconditionally calls
/// `playNext()` after anything finishes, and when nothing was displaced
/// (true for a one-shot forest clip played while the radio was idle),
/// `_takeNext()` falls through to the music scheduler and starts a real
/// song. That is correct behavior for the radio's own DJ experience, but
/// wrong for "just play this one forest clip, then be quiet" — the radio
/// would start playing music right after (sometimes seemingly instead of)
/// the forest narration the visitor actually asked for.
///
/// The fix is NOT a second radio system — it's recognizing forest audio
/// was never radio content at all. This controller owns its own single
/// `AudioPlayer` (ElevenLabs URLs) + `FlutterTts` (spoken-text fallback,
/// mirroring the exact pattern `SpeciesDetailScreen` and
/// `ForestTrailDetailScreen`'s Trail Audio Tour already use successfully),
/// completely independent of the radio engine's queue/rotation/scheduler.
/// It coordinates with the radio using ONLY its existing, already-defined
/// `pause()`/`resume()` (never its `play()`/`requestInterruption()`/queue):
/// if the radio was actively playing when forest audio is requested, it is
/// paused (not stopped — session/position preserved) and resumed when the
/// forest clip finishes; if the radio wasn't playing, it stays untouched
/// and is never auto-started.
///
/// One shared instance for the whole Ocala Forest Explorer (same lifecycle
/// shape as `ForestExperienceController`) so a manual "Listen" tap and a
/// GPS-triggered arrival narration never run two competing players, and
/// every screen's "🌲 Forest Audio" bar reflects the same live state.
class ForestAudioState {
  const ForestAudioState({this.title, this.isActive = false, this.isSpeaking = false});
  final String? title;

  /// True once something has been loaded — drives whether the "🌲 Forest
  /// Audio" bar shows at all.
  final bool isActive;

  /// True while using on-device TTS (no player stream to watch for
  /// play/pause state, so the UI reads this instead).
  final bool isSpeaking;

  ForestAudioState copyWith({String? title, bool? isActive, bool? isSpeaking}) =>
      ForestAudioState(
        title: title ?? this.title,
        isActive: isActive ?? this.isActive,
        isSpeaking: isSpeaking ?? this.isSpeaking,
      );
}

class ForestAudioController extends Notifier<ForestAudioState> {
  final AudioPlayer player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  bool _wasRadioPlaying = false;
  bool _usingTts = false;
  String? _lastSpokenText;

  bool get usingTts => _usingTts;

  @override
  ForestAudioState build() {
    _tts.setCompletionHandler(_onFinished);
    final sub = player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _onFinished();
    });
    ref.onDispose(() {
      sub.cancel();
      player.dispose();
      _tts.stop();
    });
    return const ForestAudioState();
  }

  /// Plays one piece of forest content — an ElevenLabs [audioUrl] if one
  /// exists, else [spokenText] via on-device TTS. Never touches the radio
  /// engine's queue; only pauses/resumes it around this one clip.
  Future<void> play({required String title, String? audioUrl, String? spokenText}) async {
    await _stopPlayback();

    final radioController = ref.read(radioEngineControllerProvider.notifier);
    final radioPlaying =
        ref.read(radioEngineControllerProvider).status == PlaybackStatus.playing;
    _wasRadioPlaying = radioPlaying;
    if (radioPlaying) radioController.pause();

    final url = (audioUrl ?? '').trim();
    final text = (spokenText ?? '').trim();
    if (url.isEmpty && text.isEmpty) {
      // Nothing to actually play — don't leave the radio paused for nothing.
      await _restoreRadioIfNeeded();
      return;
    }

    if (url.isNotEmpty) {
      _usingTts = false;
      state = ForestAudioState(title: title, isActive: true);
      await player.setUrl(url);
      await player.play();
    } else {
      _usingTts = true;
      _lastSpokenText = text;
      state = ForestAudioState(title: title, isActive: true, isSpeaking: true);
      await _tts.speak(text);
    }
  }

  Future<void> pause() async {
    if (_usingTts) {
      await _tts.stop(); // on-device TTS mid-utterance pause isn't reliably
      // supported across platforms; stopping is the honest behavior here.
      state = state.copyWith(isSpeaking: false);
    } else {
      await player.pause();
    }
  }

  Future<void> resume() async {
    if (_usingTts) {
      if ((_lastSpokenText ?? '').isNotEmpty) {
        state = state.copyWith(isSpeaking: true);
        await _tts.speak(_lastSpokenText!);
      }
    } else {
      await player.play();
    }
  }

  Future<void> replay() async {
    if (_usingTts) {
      if ((_lastSpokenText ?? '').isNotEmpty) {
        await _tts.stop();
        state = state.copyWith(isSpeaking: true);
        await _tts.speak(_lastSpokenText!);
      }
    } else {
      await player.seek(Duration.zero);
      await player.play();
    }
  }

  /// Stops forest audio entirely (screen disposed / navigated away while
  /// playing) and restores the radio to exactly the state it was in
  /// before, per the app's existing pause/resume behavior.
  Future<void> stop() async {
    await _stopPlayback();
    await _restoreRadioIfNeeded();
  }

  Future<void> _onFinished() async {
    state = const ForestAudioState();
    await _restoreRadioIfNeeded();
  }

  Future<void> _stopPlayback() async {
    if (_usingTts) {
      await _tts.stop();
    } else {
      await player.stop();
    }
    state = const ForestAudioState();
  }

  Future<void> _restoreRadioIfNeeded() async {
    if (_wasRadioPlaying) {
      ref.read(radioEngineControllerProvider.notifier).resume();
    }
    _wasRadioPlaying = false;
  }
}

final forestAudioControllerProvider =
    NotifierProvider<ForestAudioController, ForestAudioState>(ForestAudioController.new);
