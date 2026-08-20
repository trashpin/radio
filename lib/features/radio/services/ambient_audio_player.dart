import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Plays a very quiet, looping ambient bed (flowing water, birds, ...)
/// underneath an Explore narration segment. Completely independent of
/// [AudioPlayerPort]'s narration/music player -- never pauses, stops, or
/// otherwise touches it -- so this is purely an additive background layer,
/// not a second narration/music system. Abstracted (mirrors [Speaker]/
/// [TtsSpeaker] in `radio_audio_service.dart`) so tests can inject a fake
/// without touching platform audio channels.
abstract class AmbientPlayer {
  /// Fades in and loops [url]. A no-op if [url] is already playing.
  Future<void> play(String url);

  /// Fades out and stops. Safe to call when nothing is playing.
  Future<void> stop();

  Future<void> dispose();
}

/// Default [AmbientPlayer], backed by its own `just_audio` [AudioPlayer]
/// instance (separate from the one [AudioPlayerPort] uses for narration/
/// music) so simultaneous playback needs no platform-level audio mixing of
/// its own -- `just_audio` already supports multiple concurrent players.
class JustAudioAmbientPlayer implements AmbientPlayer {
  JustAudioAmbientPlayer({AudioPlayer Function()? playerFactory})
      : _playerFactory = playerFactory ?? AudioPlayer.new;

  final AudioPlayer Function() _playerFactory;

  /// Constructing `just_audio`'s [AudioPlayer] touches a platform channel
  /// (mirrors [TtsSpeaker]'s own lazy `FlutterTts` — see its doc comment) —
  /// so nothing happens until the ambient layer is actually needed, and a
  /// plain unit test that never triggers Explore narration with an ambient
  /// association never touches a platform channel at all.
  AudioPlayer? _player;
  AudioPlayer _ensure() => _player ??= _playerFactory();

  String? _currentUrl;
  Timer? _fadeTimer;

  /// Deliberately very low -- spec: "narration must always be clearly
  /// understandable... never compete with DJ Sunny or the main narrator."
  static const double kTargetVolume = 0.12;
  static const Duration _kFadeDuration = Duration(milliseconds: 900);
  static const int _kFadeSteps = 12;

  @override
  Future<void> play(String url) async {
    final player = _ensure();
    if (_currentUrl == url && player.playing) return;
    _fadeTimer?.cancel();
    _currentUrl = url;
    try {
      await player.setLoopMode(LoopMode.all);
      await player.setVolume(0);
      await player.setUrl(url);
      unawaited(player.play());
      await _fadeTo(player, kTargetVolume);
    } catch (_) {
      // A bad/missing ambient clip must never break narration -- just skip it.
      _currentUrl = null;
    }
  }

  @override
  Future<void> stop() async {
    final player = _player;
    if (player == null || (_currentUrl == null && !player.playing)) return;
    _currentUrl = null;
    await _fadeTo(player, 0);
    try {
      await player.stop();
    } catch (_) {}
  }

  Future<void> _fadeTo(AudioPlayer player, double target) async {
    _fadeTimer?.cancel();
    final start = player.volume;
    if (start == target) return;
    final stepMs = (_kFadeDuration.inMilliseconds / _kFadeSteps).round();
    final completer = Completer<void>();
    var step = 0;
    _fadeTimer = Timer.periodic(Duration(milliseconds: stepMs), (t) async {
      step++;
      final v = start + (target - start) * (step / _kFadeSteps);
      try {
        await player.setVolume(v.clamp(0.0, 1.0));
      } catch (_) {}
      if (step >= _kFadeSteps) {
        t.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  @override
  Future<void> dispose() async {
    _fadeTimer?.cancel();
    final player = _player;
    if (player == null) return;
    try {
      await player.dispose();
    } catch (_) {}
  }
}
