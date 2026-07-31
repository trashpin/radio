import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:explorer_os_mobile/features/nearby_gems/models/nearby_gem.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/events/radio_event.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';

/// State of a Nearby Gem narration on the ExplorerOS Radio "Now Playing" view.
class GemNarrationState {
  const GemNarrationState({this.gem, this.narrating = false});
  final NearbyGem? gem;
  final bool narrating;
  bool get active => gem != null;
}

/// Narrates an admin-curated Nearby Gem through the SAME audio engine used for
/// park stories:
///  • If the gem has a prerecorded/generated [NearbyGem.narrationUrl], it's
///    injected through the radio engine's interruption path (interrupt music →
///    play the recording → resume the music from the exact spot).
///  • Otherwise it speaks the gem's [NearbyGem.narrationText] (dedicated script,
///    then the Long Description, then the short description) via on-device TTS —
///    the same fallback the "What's Near Me" and "I See Something" reports use.
///
/// While narrating, the radio screen expands the gem's featured image into the
/// Now Playing hero; when narration finishes it collapses smoothly back to the
/// radio interface.
class GemNarrationController extends Notifier<GemNarrationState> {
  final FlutterTts _tts = FlutterTts();
  bool _wired = false;
  bool _wasPlaying = false; // TTS path only
  String? _segId; // active recorded-narration segment id
  Timer? _fallback;
  StreamSubscription<RadioEvent>? _events;

  @override
  GemNarrationState build() => const GemNarrationState();

  void _wire() {
    if (_wired) return;
    _wired = true;
    // NOTE: the TTS path is driven by a duration TIMER (see _speak), NOT by
    // flutter_tts's completion/error callbacks. On web those callbacks fire
    // almost instantly (SpeechSynthesis errors/completes synchronously), which
    // would collapse the Now Playing view before it ever renders. The timer
    // keeps the gem's story on air for its full narration duration on every
    // platform.
    // When the engine finishes our recorded narration segment, drop the
    // "narrating" flag (the engine resumes music on its own).
    _events = ref.read(radioEngineServiceProvider).events.listen((e) {
      if (_segId != null && e is SegmentCompleted && e.segment.id == _segId) {
        _segId = null;
        if (state.gem != null) {
          state = GemNarrationState(gem: state.gem);
        }
      }
    });
    ref.onDispose(() {
      _events?.cancel();
      _fallback?.cancel();
    });
  }

  /// Begins narrating [gem] on the radio. Safe to call repeatedly — a new gem
  /// immediately supersedes any in-progress gem narration.
  Future<void> narrateGem(NearbyGem gem) async {
    _wire();
    _fallback?.cancel();
    // Expand the Now Playing hero immediately (before any async work).
    state = GemNarrationState(gem: gem, narrating: true);
    // End any in-progress spoken narration so tapping a new gem switches
    // immediately instead of talking over it.
    try {
      await _tts.stop();
    } catch (_) {}

    if (gem.hasAudio) {
      _segId = 'gem:${gem.id}:${DateTime.now().millisecondsSinceEpoch}';
      final radio = ref.read(radioEngineControllerProvider.notifier);
      radio.requestInterruption(
        AudioSegment(
          id: _segId!,
          title: gem.name,
          artist: gem.category,
          type: AudioSegmentType.narration,
          priority: PlaybackPriority.scheduledAnnouncement,
          audioUrl: gem.narrationUrl,
          interruptible: true,
          resumeAfter: true,
        ),
      );
      // If the radio was idle, start it so the report plays immediately.
      if (ref.read(radioEngineControllerProvider).status !=
          PlaybackStatus.playing) {
        radio.play();
      }
    } else {
      final text = gem.narrationText;
      if (text == null) {
        // Nothing to say — collapse straight back to the radio.
        state = GemNarrationState(gem: gem);
        return;
      }
      await _speak(text);
    }
  }

  Future<void> _speak(String script) async {
    final controller = ref.read(radioEngineControllerProvider.notifier);
    _wasPlaying =
        ref.read(radioEngineControllerProvider).status ==
        PlaybackStatus.playing;
    if (_wasPlaying) controller.pause();
    // Keep the Now Playing story on air for its estimated narration duration.
    // A timer (not the TTS callback) is the source of truth so the view is
    // reliable even where on-device speech is unavailable (e.g. web).
    final secs = (script.split(RegExp(r'\s+')).length / 2.6).round().clamp(
      12,
      240,
    );
    _fallback = Timer(Duration(seconds: secs), _finishTts);
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      await _tts.speak(script);
    } catch (_) {
      // Speech unavailable — the timer still returns to the radio on schedule.
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
    if (state.gem != null) {
      state = GemNarrationState(gem: state.gem);
    }
  }

  /// Dismiss the gem entirely (back to the normal radio interface).
  Future<void> clear() async {
    if (_segId != null) {
      _segId = null;
      try {
        ref.read(radioEngineControllerProvider.notifier).skip();
      } catch (_) {}
    } else {
      try {
        await _tts.stop();
      } catch (_) {}
      _finishTts();
    }
    state = const GemNarrationState();
  }
}

final gemNarrationControllerProvider =
    NotifierProvider<GemNarrationController, GemNarrationState>(
      GemNarrationController.new,
    );
