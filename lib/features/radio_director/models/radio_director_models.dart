/// Every kind of audio event the Radio Director can choose to play, with its
/// base priority. Highest priority always wins; music fills empty time.
enum RadioEventType {
  arrival(100),
  safety(95),
  approach(90),
  wildlife(80),
  historicSite(75),
  departure(70),
  hiddenGem(60),
  scenicView(50),
  interestingFact(40),
  randomStory(30),
  music(0);

  const RadioEventType(this.basePriority);
  final int basePriority;

  bool get isNarration => this != RadioEventType.music;

  /// GPS trigger events must play regardless of the silence window.
  bool get isTrigger =>
      this == RadioEventType.arrival ||
      this == RadioEventType.approach ||
      this == RadioEventType.departure ||
      this == RadioEventType.safety;
}

/// Guide personalities bias which content the Director favors.
enum RadioGuidePersonality {
  explorer('Explorer'),
  naturalist('Naturalist'),
  historian('Historian'),
  roadTrip('Road Trip'),
  family('Family'),
  photographer('Photographer'),
  adventure('Adventure');

  const RadioGuidePersonality(this.label);
  final String label;

  /// Priority multiplier this personality applies to a given event type.
  double multiplier(RadioEventType t) {
    switch (this) {
      case RadioGuidePersonality.explorer:
        return 1.0; // balanced
      case RadioGuidePersonality.naturalist:
        return t == RadioEventType.wildlife ? 1.6 : 1.0;
      case RadioGuidePersonality.historian:
        return (t == RadioEventType.historicSite ||
                t == RadioEventType.randomStory)
            ? 1.6
            : 1.0;
      case RadioGuidePersonality.roadTrip:
        // Mostly music: damp all non-essential narration.
        return t.isTrigger ? 1.0 : 0.4;
      case RadioGuidePersonality.family:
        return t == RadioEventType.interestingFact ? 1.7 : 1.0;
      case RadioGuidePersonality.photographer:
        return t == RadioEventType.scenicView ? 1.7 : 1.0;
      case RadioGuidePersonality.adventure:
        return (t == RadioEventType.hiddenGem ||
                t == RadioEventType.scenicView)
            ? 1.6
            : 1.0;
    }
  }
}

/// A low/normal/high (or off) frequency knob for a content family.
enum RadioFrequency {
  off(0.0),
  low(0.6),
  normal(1.0),
  high(1.5);

  const RadioFrequency(this.scale);
  final double scale;
}

/// The visitor's radio preferences (the only "settings" they might touch).
class RadioPreferences {
  const RadioPreferences({
    this.musicPercent = 60,
    this.narrationPercent = 70,
    this.storyFrequency = RadioFrequency.normal,
    this.wildlifeFrequency = RadioFrequency.normal,
    this.historyFrequency = RadioFrequency.normal,
  });

  /// 0–100.
  final int musicPercent;

  /// 0–100. At 0, only GPS-trigger/safety narration plays.
  final int narrationPercent;

  final RadioFrequency storyFrequency;
  final RadioFrequency wildlifeFrequency;
  final RadioFrequency historyFrequency;

  RadioPreferences copyWith({
    int? musicPercent,
    int? narrationPercent,
    RadioFrequency? storyFrequency,
    RadioFrequency? wildlifeFrequency,
    RadioFrequency? historyFrequency,
  }) =>
      RadioPreferences(
        musicPercent: musicPercent ?? this.musicPercent,
        narrationPercent: narrationPercent ?? this.narrationPercent,
        storyFrequency: storyFrequency ?? this.storyFrequency,
        wildlifeFrequency: wildlifeFrequency ?? this.wildlifeFrequency,
        historyFrequency: historyFrequency ?? this.historyFrequency,
      );

  /// Preference-driven scale for an event type (0 disables the family).
  double scale(RadioEventType t) {
    if (t == RadioEventType.music) return 1.0;
    if (narrationPercent <= 0 && !t.isTrigger) return 0.0;
    final narrationScale = narrationPercent / 100.0;
    switch (t) {
      case RadioEventType.randomStory:
        return narrationScale * storyFrequency.scale;
      case RadioEventType.wildlife:
        return narrationScale * wildlifeFrequency.scale;
      case RadioEventType.historicSite:
        return narrationScale * historyFrequency.scale;
      default:
        // Triggers are not damped below 1.0 by the narration slider (they must
        // still fire), but non-trigger extras follow the slider.
        return t.isTrigger ? 1.0 : narrationScale;
    }
  }
}

/// The vehicle/visitor state, which lightly tunes how chatty the Director is.
enum RadioPlaybackState {
  driving,
  stopped,
  parked,
  walking,
  visitorCenter,
  trail,
  scenicOverlook,
  campground;

  /// Multiplier on the minimum quiet window. Stopped/parked/at-a-POI → more
  /// narration allowed (shorter quiet); fast driving → keep it calmer.
  double quietMultiplier() {
    switch (this) {
      case RadioPlaybackState.stopped:
      case RadioPlaybackState.parked:
      case RadioPlaybackState.visitorCenter:
      case RadioPlaybackState.scenicOverlook:
        return 0.5;
      case RadioPlaybackState.walking:
      case RadioPlaybackState.trail:
      case RadioPlaybackState.campground:
        return 0.75;
      case RadioPlaybackState.driving:
        return 1.0;
    }
  }
}

/// A single thing the Director could choose to play right now.
class RadioCandidate {
  const RadioCandidate({
    required this.type,
    required this.id,
    required this.title,
    required this.triggerKey,
    this.audioUrl,
    this.destinationCode,
    this.distanceMeters,
  });

  final RadioEventType type;
  final String id;
  final String title;

  /// Unique key for anti-repeat within a visit (e.g. `arrival:silver_springs`).
  final String triggerKey;

  final String? audioUrl;
  final String? destinationCode;
  final double? distanceMeters;
}

/// Tunable configuration (exposed in the admin Radio Director settings).
class RadioDirectorConfig {
  const RadioDirectorConfig({
    this.minQuietSeconds = 180,
    this.interruptThreshold = 90,
    this.gpsTriggerDistanceMeters = 1609,
    this.fadeDurationMs = 1000,
    this.musicVolume = 0.8,
    this.narrationVolume = 1.0,
    this.priorityOverrides = const {},
  });

  /// Minimum uninterrupted music between (non-urgent) narrations.
  final int minQuietSeconds;

  /// Priority at/above which an event bypasses the silence window and may
  /// interrupt an in-progress narration.
  final int interruptThreshold;

  final double gpsTriggerDistanceMeters;
  final int fadeDurationMs;
  final double musicVolume;
  final double narrationVolume;

  /// Per-type priority overrides (admin-tunable).
  final Map<RadioEventType, int> priorityOverrides;

  RadioDirectorConfig copyWith({
    int? minQuietSeconds,
    int? interruptThreshold,
    double? gpsTriggerDistanceMeters,
    int? fadeDurationMs,
    double? musicVolume,
    double? narrationVolume,
    Map<RadioEventType, int>? priorityOverrides,
  }) =>
      RadioDirectorConfig(
        minQuietSeconds: minQuietSeconds ?? this.minQuietSeconds,
        interruptThreshold: interruptThreshold ?? this.interruptThreshold,
        gpsTriggerDistanceMeters:
            gpsTriggerDistanceMeters ?? this.gpsTriggerDistanceMeters,
        fadeDurationMs: fadeDurationMs ?? this.fadeDurationMs,
        musicVolume: musicVolume ?? this.musicVolume,
        narrationVolume: narrationVolume ?? this.narrationVolume,
        priorityOverrides: priorityOverrides ?? this.priorityOverrides,
      );
}

/// The inputs the Director evaluates each tick.
class RadioContext {
  const RadioContext({
    required this.now,
    required this.narrationPlaying,
    required this.musicPlaying,
    required this.secondsSinceLastNarration,
    required this.candidates,
    this.guide = RadioGuidePersonality.explorer,
    this.preferences = const RadioPreferences(),
    this.playbackState = RadioPlaybackState.driving,
    this.playedKeys = const {},
    this.currentNarrationPriority,
  });

  final DateTime now;
  final bool narrationPlaying;
  final bool musicPlaying;
  final double secondsSinceLastNarration;
  final List<RadioCandidate> candidates;
  final RadioGuidePersonality guide;
  final RadioPreferences preferences;
  final RadioPlaybackState playbackState;
  final Set<String> playedKeys;

  /// Priority of the narration currently playing (for interrupt decisions).
  final int? currentNarrationPriority;
}

/// What the Director decided to do this tick.
enum RadioAction { playNarration, keepCurrent, keepMusic, startMusic }

class RadioDecision {
  const RadioDecision(this.action, {this.candidate, this.score = 0, this.reason = ''});

  final RadioAction action;
  final RadioCandidate? candidate;
  final double score;
  final String reason;

  @override
  String toString() {
    final what = candidate != null ? ' ${candidate!.title}' : '';
    return '${action.name}$what'
        '${candidate != null ? ' (p${score.round()})' : ''}'
        '${reason.isNotEmpty ? ' · $reason' : ''}';
  }
}
