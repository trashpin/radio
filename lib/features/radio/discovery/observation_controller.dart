import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/media/data/media_repository.dart';
import 'package:explorer_os_mobile/features/narration/data/narration_repository.dart';
import 'package:explorer_os_mobile/features/narration/services/narration_script_composer.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/events/radio_event.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';

/// State of the "I See Something" discovery overlay on the radio.
class ObservationState {
  const ObservationState({this.species, this.narrating = false});
  final Species? species;
  final bool narrating;
  bool get active => species != null;
}

/// Drives the discovery experience. Selecting a subject narrates the species and
/// then returns to the music:
///  • If a recorded voiceover exists (DJ Brittney/ElevenLabs in `narrations`/
///    `media`), it's injected through the radio engine's interruption path —
///    the same proven mechanism the scheduler uses (interrupt music → play the
///    recording → resume automatically).
///  • Otherwise it pauses the radio and speaks a composed script via on-device
///    TTS, resuming when done.
class ObservationController extends Notifier<ObservationState> {
  final FlutterTts _tts = FlutterTts();
  static const _composer = NarrationScriptComposer();
  bool _wired = false;
  bool _wasPlaying = false; // TTS path only
  String? _segId; // active recorded-narration segment id
  Timer? _fallback;
  StreamSubscription<RadioEvent>? _events;

  @override
  ObservationState build() => const ObservationState();

  void _wire() {
    if (_wired) return;
    _wired = true;
    _tts.setCompletionHandler(_finishTts);
    _tts.setErrorHandler((_) => _finishTts());
    // When the engine finishes our recorded narration segment, drop the
    // "narrating" state (the engine resumes music on its own).
    _events = ref.read(radioEngineServiceProvider).events.listen((e) {
      if (_segId != null &&
          e is SegmentCompleted &&
          e.segment.id == _segId) {
        _segId = null;
        if (state.species != null) {
          state = ObservationState(species: state.species, narrating: false);
        }
      }
    });
    ref.onDispose(() => _events?.cancel());
  }

  Future<void> observe(Species s) async {
    _wire();
    _fallback?.cancel();
    // End any in-progress spoken (TTS) narration so a new subject switches
    // immediately instead of talking over it.
    try {
      await _tts.stop();
    } catch (_) {}
    final url = await _narrationUrl(s);
    state = ObservationState(species: s, narrating: true);

    if (url != null && url.isNotEmpty) {
      // Recorded voiceover through the engine (interrupt → play → resume).
      _segId = 'obs:${s.id}:${DateTime.now().millisecondsSinceEpoch}';
      ref.read(radioEngineControllerProvider.notifier).requestInterruption(
            AudioSegment(
              id: _segId!,
              title: s.commonName,
              artist: s.scientificName,
              type: AudioSegmentType.narration,
              priority: PlaybackPriority.scheduledAnnouncement,
              audioUrl: url,
              interruptible: true,
              resumeAfter: true,
            ),
          );
    } else {
      await _speak(s);
    }
  }

  Future<String?> _narrationUrl(Species s) async {
    try {
      final n = await ref.read(narrationRepositoryProvider).bestForContent(s.id);
      if (n?.audioUrl != null && n!.audioUrl!.isNotEmpty) return n.audioUrl;
    } catch (_) {}
    try {
      return await ref.read(mediaRepositoryProvider).narrationUrlForSpecies(s.id);
    } catch (_) {
      return null;
    }
  }

  // ── TTS fallback (species without a recording) ──
  Future<void> _speak(Species s) async {
    final controller = ref.read(radioEngineControllerProvider.notifier);
    _wasPlaying = ref.read(radioEngineControllerProvider).status ==
        PlaybackStatus.playing;
    if (_wasPlaying) controller.pause();
    final script = _composer.composeForSpecies(s);
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
    } catch (_) {}
    final secs = _composer.estimateSeconds(script).clamp(20, 180);
    _fallback = Timer(Duration(seconds: secs + 6), _finishTts);
    try {
      await _tts.speak(script);
    } catch (_) {
      _finishTts();
    }
  }

  void _finishTts() {
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
    if (_segId != null) {
      _segId = null;
      // Skip the interruption; the engine resumes music.
      try {
        ref.read(radioEngineControllerProvider.notifier).skip();
      } catch (_) {}
      if (state.species != null) {
        state = ObservationState(species: state.species, narrating: false);
      }
    } else {
      try {
        await _tts.stop();
      } catch (_) {}
      _finishTts();
    }
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
