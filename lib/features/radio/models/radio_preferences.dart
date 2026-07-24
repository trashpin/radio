import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';

/// Immutable listener preferences for the Radio Engine.
///
/// Managed by [RadioPreferenceService]. Content toggles let the AI Producer/
/// schedulers skip categories the listener muted; [volume]/[muted] feed the
/// AudioFocusManager. Immutable with [copyWith] for predictable state.
class RadioPreferences {
  const RadioPreferences({
    this.narrationsEnabled = true,
    this.announcementsEnabled = true,
    this.weatherEnabled = true,
    this.wildlifeEnabled = true,
    this.ambientEnabled = true,
    this.commercialsEnabled = true,
    this.mutedCategories = const {},
    this.volume = 1.0,
    this.muted = false,
  });

  final bool narrationsEnabled;
  final bool announcementsEnabled;
  final bool weatherEnabled;
  final bool wildlifeEnabled;
  final bool ambientEnabled;
  final bool commercialsEnabled;
  final Set<AudioCategory> mutedCategories;

  /// 0.0–1.0.
  final double volume;
  final bool muted;

  bool allows(AudioCategory category) => !mutedCategories.contains(category);

  RadioPreferences copyWith({
    bool? narrationsEnabled,
    bool? announcementsEnabled,
    bool? weatherEnabled,
    bool? wildlifeEnabled,
    bool? ambientEnabled,
    bool? commercialsEnabled,
    Set<AudioCategory>? mutedCategories,
    double? volume,
    bool? muted,
  }) {
    return RadioPreferences(
      narrationsEnabled: narrationsEnabled ?? this.narrationsEnabled,
      announcementsEnabled: announcementsEnabled ?? this.announcementsEnabled,
      weatherEnabled: weatherEnabled ?? this.weatherEnabled,
      wildlifeEnabled: wildlifeEnabled ?? this.wildlifeEnabled,
      ambientEnabled: ambientEnabled ?? this.ambientEnabled,
      commercialsEnabled: commercialsEnabled ?? this.commercialsEnabled,
      mutedCategories: mutedCategories ?? this.mutedCategories,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
    );
  }

  static const defaults = RadioPreferences();
}
