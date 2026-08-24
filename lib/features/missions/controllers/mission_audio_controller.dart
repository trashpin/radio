import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_state.dart';

/// Marion County Adventures' own narration player — the SAME design as
/// `DiscoverAudioController`/`ForestAudioController` (own `AudioPlayer` +
/// `FlutterTts` fallback, coordinating with the radio ONLY via its existing
/// `pause()`/`resume()`), applied to mission narration instead. A separate
/// instance per this codebase's own established convention (one per feature
/// area, so each feature's "now playing" bar only ever reflects its own
/// content) — the same battle-tested duck/resume mechanism, not a new one,
/// and never a second RADIO or audio system (spec Phase 8: "MUSIC -> FADE
/// DOWN -> STORY -> FADE UP -> MUSIC" — this app's existing equivalent of a
/// volume fade is pause/resume, exactly as already used for "Hear About It").
class MissionAudioState {
  const MissionAudioState({this.title, this.isActive = false, this.isSpeaking = false});
  final String? title;
  final bool isActive;
  final bool isSpeaking;

  MissionAudioState copyWith({String? title, bool? isActive, bool? isSpeaking}) =>
      MissionAudioState(
        title: title ?? this.title,
        isActive: isActive ?? this.isActive,
        isSpeaking: isSpeaking ?? this.isSpeaking,
      );
}

class MissionAudioController extends Notifier<MissionAudioState> {
  final AudioPlayer player = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  bool _wasRadioPlaying = false;
  bool _usingTts = false;
  String? _lastSpokenText;
  void Function()? _onFinishedCallback;

  bool get usingTts => _usingTts;
  bool get isPlaying => state.isActive;

  @override
  MissionAudioState build() {
    _tts.setCompletionHandler(_onFinished);
    final sub = player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _onFinished();
    });
    ref.onDispose(() {
      sub.cancel();
      player.dispose();
      _tts.stop();
    });
    return const MissionAudioState();
  }

  /// Plays one narration beat — an ElevenLabs [audioUrl] if one exists, else
  /// [spokenText] via on-device TTS. Ducks (pauses) the radio around this
  /// one clip and resumes it afterward; never touches the radio's queue.
  /// [onFinished] lets the mission runtime advance its state machine only
  /// once the audio has genuinely completed, not merely been requested.
  Future<void> play({
    required String title,
    String? audioUrl,
    String? spokenText,
    void Function()? onFinished,
  }) async {
    await _stopPlayback();
    _onFinishedCallback = onFinished;

    final radioController = ref.read(radioEngineControllerProvider.notifier);
    final radioPlaying =
        ref.read(radioEngineControllerProvider).status == PlaybackStatus.playing;
    _wasRadioPlaying = radioPlaying;
    if (radioPlaying) radioController.pause();

    final url = (audioUrl ?? '').trim();
    final text = (spokenText ?? '').trim();
    if (url.isEmpty && text.isEmpty) {
      await _restoreRadioIfNeeded();
      _onFinishedCallback?.call();
      _onFinishedCallback = null;
      return;
    }

    if (url.isNotEmpty) {
      _usingTts = false;
      state = MissionAudioState(title: title, isActive: true);
      await player.setUrl(url);
      await player.play();
    } else {
      _usingTts = true;
      _lastSpokenText = text;
      state = MissionAudioState(title: title, isActive: true, isSpeaking: true);
      await _tts.speak(text);
    }
  }

  Future<void> replay(String title) async {
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
    state = const MissionAudioState();
    await _restoreRadioIfNeeded();
    _onFinishedCallback?.call();
    _onFinishedCallback = null;
  }

  Future<void> _stopPlayback() async {
    if (_usingTts) {
      await _tts.stop();
    } else {
      await player.stop();
    }
    state = const MissionAudioState();
  }

  Future<void> _restoreRadioIfNeeded() async {
    if (_wasRadioPlaying) {
      ref.read(radioEngineControllerProvider.notifier).resume();
    }
    _wasRadioPlaying = false;
  }
}

final missionAudioControllerProvider =
    NotifierProvider<MissionAudioController, MissionAudioState>(MissionAudioController.new);
