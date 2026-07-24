/// Audio focus + volume/mute intent for the Radio Engine.
///
/// WHY THIS EXISTS: playback must cooperate with the OS (ducking for
/// navigation prompts/calls, pausing on focus loss) and expose volume/mute.
/// This holds that INTENT; a real implementation (via `audio_service` /
/// platform audio focus) plugs in behind the same API — the engine stays the
/// same. Bluetooth/Android Auto/CarPlay route through the OS audio session this
/// manager will own.
class AudioFocusManager {
  double _volume = 1.0;
  bool _muted = false;
  bool _hasFocus = false;

  double get volume => _volume;
  bool get isMuted => _muted;
  bool get hasFocus => _hasFocus;

  /// Volume actually applied (0 when muted).
  double get effectiveVolume => _muted ? 0 : _volume;

  void setVolume(double volume) => _volume = volume.clamp(0, 1).toDouble();
  void mute() => _muted = true;
  void unmute() => _muted = false;

  /// Requests OS audio focus (stub: records intent). Returns whether granted.
  bool requestFocus() {
    _hasFocus = true;
    return true;
  }

  void abandonFocus() => _hasFocus = false;
}
