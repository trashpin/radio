import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:explorer_os_mobile/features/discover_area/models/narratable_item.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/events/radio_event.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';

/// State of the Audio Experience sequence playing on the radio engine.
class AudioExperienceState {
  const AudioExperienceState({this.items = const [], this.index = 0, this.playing = false});

  final List<NarratableItem> items;
  final int index;
  final bool playing;

  NarratableItem? get current => index >= 0 && index < items.length ? items[index] : null;
  bool get hasNext => index + 1 < items.length;
  bool get active => items.isNotEmpty;

  AudioExperienceState copyWith({int? index, bool? playing}) => AudioExperienceState(
        items: items,
        index: index ?? this.index,
        playing: playing ?? this.playing,
      );
}

/// Plays the Audio Experience's mixed sequence (area intro, history, wildlife,
/// nature, facts, attractions) end to end — the exact same recorded-audio/
/// TTS-fallback/auto-advance mechanism as [AreaContentPlaybackController],
/// generalized from content blocks to any [NarratableItem].
class AudioExperienceController extends Notifier<AudioExperienceState> {
  final FlutterTts _tts = FlutterTts();
  bool _wired = false;
  bool _wasPlaying = false;
  String? _segId;
  Timer? _fallback;
  StreamSubscription<RadioEvent>? _events;

  @override
  AudioExperienceState build() {
    ref.onDispose(() {
      _events?.cancel();
      _fallback?.cancel();
    });
    return const AudioExperienceState();
  }

  void _wire() {
    if (_wired) return;
    _wired = true;
    _events = ref.read(radioEngineServiceProvider).events.listen((e) {
      if (_segId != null && e is SegmentCompleted && e.segment.id == _segId) {
        _segId = null;
        _advance();
      }
    });
  }

  Future<void> play(List<NarratableItem> items) async {
    _wire();
    _fallback?.cancel();
    try {
      await _tts.stop();
    } catch (_) {}
    state = AudioExperienceState(items: items, index: 0, playing: true);
    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    final item = state.current;
    if (item == null) {
      state = state.copyWith(playing: false);
      return;
    }
    if (item.hasAudio) {
      _segId = 'audio-experience:${DateTime.now().millisecondsSinceEpoch}';
      final radio = ref.read(radioEngineControllerProvider.notifier);
      radio.requestInterruption(
        AudioSegment(
          id: _segId!,
          title: item.title,
          type: AudioSegmentType.narration,
          priority: PlaybackPriority.scheduledAnnouncement,
          audioUrl: item.audioUrl,
          interruptible: true,
          resumeAfter: true,
        ),
      );
      if (ref.read(radioEngineControllerProvider).status != PlaybackStatus.playing) {
        radio.play();
      }
    } else if (item.hasNarration) {
      await _speak(item.script!);
    } else {
      _advance();
    }
  }

  Future<void> _speak(String script) async {
    final controller = ref.read(radioEngineControllerProvider.notifier);
    _wasPlaying =
        ref.read(radioEngineControllerProvider).status == PlaybackStatus.playing;
    if (_wasPlaying) controller.pause();
    final secs = (script.split(RegExp(r'\s+')).length / 2.6).round().clamp(6, 240);
    _fallback = Timer(Duration(seconds: secs), _finishSpoken);
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      await _tts.speak(script);
    } catch (_) {}
  }

  void _finishSpoken() {
    _fallback?.cancel();
    _fallback = null;
    if (_wasPlaying) {
      try {
        ref.read(radioEngineControllerProvider.notifier).resume();
      } catch (_) {}
      _wasPlaying = false;
    }
    _advance();
  }

  void _advance() {
    if (!state.hasNext) {
      state = state.copyWith(playing: false);
      return;
    }
    state = state.copyWith(index: state.index + 1);
    _playCurrent();
  }

  void skipToNext() {
    if (_segId != null) {
      _segId = null;
      try {
        ref.read(radioEngineControllerProvider.notifier).skip();
      } catch (_) {}
    } else {
      try {
        _tts.stop();
      } catch (_) {}
      _fallback?.cancel();
    }
    _advance();
  }

  Future<void> stop() async {
    if (_segId != null) {
      _segId = null;
      try {
        ref.read(radioEngineControllerProvider.notifier).skip();
      } catch (_) {}
    } else {
      try {
        await _tts.stop();
      } catch (_) {}
      _fallback?.cancel();
      if (_wasPlaying) {
        try {
          ref.read(radioEngineControllerProvider.notifier).resume();
        } catch (_) {}
        _wasPlaying = false;
      }
    }
    state = const AudioExperienceState();
  }
}

final audioExperienceControllerProvider =
    NotifierProvider<AudioExperienceController, AudioExperienceState>(
  AudioExperienceController.new,
);
