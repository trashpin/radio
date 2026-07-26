import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/narration/services/narration_script_composer.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';

/// State of the "I See Something" discovery overlay on the radio.
class ObservationState {
  const ObservationState({this.species, this.narrating = false});
  final Species? species;
  final bool narrating;
  bool get active => species != null;
}

/// Drives the discovery experience: when the user selects an observation, it
/// ducks the radio music to ~25%, narrates the species (stored script or a
/// composed tour-guide script via TTS), then fades the music back and resumes.
class ObservationController extends Notifier<ObservationState> {
  final FlutterTts _tts = FlutterTts();
  bool _wired = false;

  @override
  ObservationState build() => const ObservationState();

  void _wire() {
    if (_wired) return;
    _wired = true;
    _tts.setCompletionHandler(_finish);
  }

  Future<void> observe(Species s) async {
    _wire();
    // Duck the radio (music keeps playing softly under the narration).
    try {
      await ref.read(audioPlayerPortProvider).setVolume(0.25);
    } catch (_) {}
    state = ObservationState(species: s, narrating: true);
    final script = const NarrationScriptComposer().composeForSpecies(s);
    try {
      await _tts.stop();
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
    } catch (_) {}
    try {
      await _tts.speak(script);
    } catch (_) {
      _finish();
    }
  }

  void _finish() {
    // Fade music back to full.
    try {
      ref.read(audioPlayerPortProvider).setVolume(1.0);
    } catch (_) {}
    if (state.species != null) {
      state = ObservationState(species: state.species, narrating: false);
    }
  }

  /// Stop narration but keep showing the observation (follow-up chips).
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
