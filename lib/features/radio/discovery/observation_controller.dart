import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/narration/services/narration_script_composer.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';

/// State of the "I See Something" discovery overlay on the radio.
class ObservationState {
  const ObservationState({this.species, this.narrating = false});
  final Species? species;
  final bool narrating;
  bool get active => species != null;
}

/// Drives the discovery experience: when the user selects an observation while
/// the radio is playing, it **pauses the music** (interrupt), narrates the
/// species aloud (composed tour-guide script via TTS), then **resumes the
/// radio exactly where it left off**. A fallback timer guarantees the radio
/// resumes even if the web TTS completion callback doesn't fire.
class ObservationController extends Notifier<ObservationState> {
  final FlutterTts _tts = FlutterTts();
  static const _composer = NarrationScriptComposer();
  bool _wired = false;
  bool _wasPlaying = false;
  Timer? _fallback;

  @override
  ObservationState build() => const ObservationState();

  void _wire() {
    if (_wired) return;
    _wired = true;
    _tts.setCompletionHandler(_finish);
    _tts.setCancelHandler(_finish);
    _tts.setErrorHandler((_) => _finish());
  }

  Future<void> observe(Species s) async {
    _wire();
    _fallback?.cancel();

    // Interrupt the radio: remember whether it was playing, then pause it so
    // the narration is clearly audible.
    final controller = ref.read(radioEngineControllerProvider.notifier);
    _wasPlaying =
        ref.read(radioEngineControllerProvider).status == PlaybackStatus.playing;
    if (_wasPlaying) controller.pause();

    state = ObservationState(species: s, narrating: true);

    final script = _composer.composeForSpecies(s);
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
    } catch (_) {/* optional tuning */}

    // Safety net: resume the radio after the estimated duration even if the
    // TTS completion callback never arrives (a known web flakiness).
    final secs = _composer.estimateSeconds(script).clamp(20, 180);
    _fallback = Timer(Duration(seconds: secs + 6), _finish);

    try {
      await _tts.speak(script);
    } catch (_) {
      _finish();
    }
  }

  void _finish() {
    _fallback?.cancel();
    _fallback = null;
    // Resume the radio exactly where it left off.
    if (_wasPlaying) {
      try {
        ref.read(radioEngineControllerProvider.notifier).resume();
      } catch (_) {}
      _wasPlaying = false;
    }
    if (state.species != null) {
      state = ObservationState(species: state.species, narrating: false);
    }
  }

  /// Stop narration early (keeps the observation on screen for follow-up chips).
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _finish();
  }

  /// Dismiss the observation entirely (back to normal Now Playing).
  Future<void> clear() async {
    await stop();
    state = const ObservationState();
  }
}

final observationControllerProvider =
    NotifierProvider<ObservationController, ObservationState>(
        ObservationController.new);
