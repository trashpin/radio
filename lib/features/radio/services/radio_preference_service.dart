import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/radio_preferences.dart';

/// Owns the listener's [RadioPreferences].
///
/// WHY THIS EXISTS: a single place for content toggles + volume/mute that the
/// schedulers, AI Producer, and AudioFocusManager consult. In-memory now;
/// persisted/synced later (via PlaybackRepository/Supabase) without changing
/// callers.
class RadioPreferenceService {
  RadioPreferences _preferences = RadioPreferences.defaults;

  RadioPreferences get preferences => _preferences;

  void update(RadioPreferences preferences) => _preferences = preferences;

  void setVolume(double volume) =>
      _preferences = _preferences.copyWith(volume: volume.clamp(0, 1));
  void setMuted(bool muted) =>
      _preferences = _preferences.copyWith(muted: muted);

  /// Whether a given [category] is currently allowed to play.
  bool allows(AudioCategory category) => _preferences.allows(category);
}
