import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/media/data/media_repository.dart';
import 'package:explorer_os_mobile/features/narration/data/narration_repository.dart';
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

/// Drives the discovery experience: selecting a subject **pauses the radio**,
/// then narrates the species — preferring a **pre-generated recorded voiceover**
/// (DJ Brittney / ElevenLabs, stored in `narrations`/`media`) and only falling
/// back to on-device text-to-speech when no recording exists — then **resumes
/// the radio** exactly where it left off.
class ObservationController extends Notifier<ObservationState> {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  static const _composer = NarrationScriptComposer();
  bool _wired = false;
  bool _wasPlaying = false;
  bool _suppress = false; // ignore player completion during teardown
  Timer? _fallback;

  @override
  ObservationState build() => const ObservationState();

  void _wire() {
    if (_wired) return;
    _wired = true;
    _tts.setCompletionHandler(_finish);
    _tts.setErrorHandler((_) => _finish());
    _player.playerStateStream.listen((st) {
      if (!_suppress && st.processingState == ProcessingState.completed) {
        _finish();
      }
    });
  }

  Future<void> observe(Species s) async {
    _wire();
    await _teardownAudio(); // stop any current narration without resuming
    _fallback?.cancel();

    final controller = ref.read(radioEngineControllerProvider.notifier);
    if (!state.narrating) {
      _wasPlaying = ref.read(radioEngineControllerProvider).status ==
          PlaybackStatus.playing;
    }
    if (_wasPlaying) controller.pause();
    state = ObservationState(species: s, narrating: true);

    // Prefer a recorded voiceover; else speak a composed script.
    final url = await _narrationUrl(s);
    if (url != null && url.isNotEmpty) {
      try {
        _suppress = false;
        await _player.setUrl(url);
        await _player.play(); // completion listener resumes the radio
        return;
      } catch (_) {/* fall through to TTS */}
    }
    await _speak(s);
  }

  Future<String?> _narrationUrl(Species s) async {
    // 1. Approved narration with audio (narrations table).
    try {
      final n = await ref.read(narrationRepositoryProvider).bestForContent(s.id);
      if (n?.audioUrl != null && n!.audioUrl!.isNotEmpty) return n.audioUrl;
    } catch (_) {}
    // 2. Linked media audio (the DJ Brittney species voiceovers).
    try {
      return await ref.read(mediaRepositoryProvider).narrationUrlForSpecies(s.id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _speak(Species s) async {
    final script = _composer.composeForSpecies(s);
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
    } catch (_) {}
    final secs = _composer.estimateSeconds(script).clamp(20, 180);
    _fallback = Timer(Duration(seconds: secs + 6), _finish);
    try {
      await _tts.speak(script);
    } catch (_) {
      _finish();
    }
  }

  Future<void> _teardownAudio() async {
    _suppress = true;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    _fallback?.cancel();
    _suppress = false;
  }

  void _finish() {
    _fallback?.cancel();
    _fallback = null;
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
    await _teardownAudio();
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
