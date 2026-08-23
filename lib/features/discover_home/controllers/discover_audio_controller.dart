import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';

/// Discover's own narration player — the exact same design as
/// `ForestAudioController` (own `AudioPlayer` + `FlutterTts` fallback,
/// coordinating with the radio ONLY via its existing `pause()`/`resume()`),
/// applied to Discover items instead of Ocala Forest content. A separate
/// instance rather than sharing ForestAudioController's, so each feature's
/// "now playing" bar only ever reflects its own content — but the same
/// battle-tested mechanism, not a new one, and never a second RADIO system.
class DiscoverAudioState {
  const DiscoverAudioState({this.title, this.isActive = false, this.isSpeaking = false});
  final String? title;
  final bool isActive;
  final bool isSpeaking;

  DiscoverAudioState copyWith({String? title, bool? isActive, bool? isSpeaking}) =>
      DiscoverAudioState(
        title: title ?? this.title,
        isActive: isActive ?? this.isActive,
        isSpeaking: isSpeaking ?? this.isSpeaking,
      );
}

class DiscoverAudioController extends Notifier<DiscoverAudioState> {
  final AudioPlayer player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  bool _wasRadioPlaying = false;
  bool _usingTts = false;
  String? _lastSpokenText;

  bool get usingTts => _usingTts;

  @override
  DiscoverAudioState build() {
    _tts.setCompletionHandler(_onFinished);
    final sub = player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _onFinished();
    });
    ref.onDispose(() {
      sub.cancel();
      player.dispose();
      _tts.stop();
    });
    return const DiscoverAudioState();
  }

  /// Plays one narration — an ElevenLabs [audioUrl] if one exists, else
  /// [spokenText] via on-device TTS. Never touches the radio engine's queue;
  /// only pauses/resumes it around this one clip.
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
      await _restoreRadioIfNeeded();
      return;
    }

    if (url.isNotEmpty) {
      _usingTts = false;
      state = DiscoverAudioState(title: title, isActive: true);
      await player.setUrl(url);
      await player.play();
    } else {
      _usingTts = true;
      _lastSpokenText = text;
      state = DiscoverAudioState(title: title, isActive: true, isSpeaking: true);
      await _tts.speak(text);
    }
  }

  Future<void> pause() async {
    if (_usingTts) {
      await _tts.stop();
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

  Future<void> stop() async {
    await _stopPlayback();
    await _restoreRadioIfNeeded();
  }

  Future<void> _onFinished() async {
    state = const DiscoverAudioState();
    await _restoreRadioIfNeeded();
  }

  Future<void> _stopPlayback() async {
    if (_usingTts) {
      await _tts.stop();
    } else {
      await player.stop();
    }
    state = const DiscoverAudioState();
  }

  Future<void> _restoreRadioIfNeeded() async {
    if (_wasRadioPlaying) {
      ref.read(radioEngineControllerProvider.notifier).resume();
    }
    _wasRadioPlaying = false;
  }
}

final discoverAudioControllerProvider =
    NotifierProvider<DiscoverAudioController, DiscoverAudioState>(DiscoverAudioController.new);
