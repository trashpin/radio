/// WHY the Producer chose what it chose.
///
/// Every [PlaybackDecision] carries a [DecisionReason] so the choice is fully
/// explainable — for debugging, analytics, and (later) an on-screen "why am I
/// hearing this?" affordance. The order mirrors the decision priority ladder.
enum DecisionReason {
  emergency,
  safety,
  navigation,
  scheduledStory,
  upcomingAttraction,
  stationIdentification,
  music,
  locationMusic,
  ambient,
  resumeMusic,
  nothingToPlay;

  /// Short human label.
  String get label {
    switch (this) {
      case DecisionReason.emergency:
        return 'Emergency alert';
      case DecisionReason.safety:
        return 'Safety warning';
      case DecisionReason.navigation:
        return 'Navigation';
      case DecisionReason.scheduledStory:
        return 'Scheduled story';
      case DecisionReason.upcomingAttraction:
        return 'Upcoming attraction';
      case DecisionReason.stationIdentification:
        return 'Station identification';
      case DecisionReason.music:
        return 'Music';
      case DecisionReason.locationMusic:
        return 'Location music';
      case DecisionReason.ambient:
        return 'Ambient';
      case DecisionReason.resumeMusic:
        return 'Resume music';
      case DecisionReason.nothingToPlay:
        return 'Nothing to play';
    }
  }

  /// A one-line rationale for the decision.
  String get description {
    switch (this) {
      case DecisionReason.emergency:
        return 'An emergency alert overrides everything and must play now.';
      case DecisionReason.safety:
        return 'A safety warning takes precedence over all non-emergency audio.';
      case DecisionReason.navigation:
        return 'A navigation/turn prompt is time-critical and interrupts music.';
      case DecisionReason.scheduledStory:
        return 'A story is due per the station cadence; it interrupts and music '
            'resumes afterwards.';
      case DecisionReason.upcomingAttraction:
        return 'The listener is approaching an attraction with location audio '
            '(GPS-ready).';
      case DecisionReason.stationIdentification:
        return 'A station identification is due per cadence.';
      case DecisionReason.music:
        return 'No higher-priority content is pending, so music continues.';
      case DecisionReason.locationMusic:
        return 'Music selected to match the current location/context.';
      case DecisionReason.ambient:
        return 'Nothing else is eligible; ambient audio fills the gap.';
      case DecisionReason.resumeMusic:
        return 'An interruption ended; the paused music resumes.';
      case DecisionReason.nothingToPlay:
        return 'No eligible audio is available to play.';
    }
  }
}
