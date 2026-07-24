/// The fixed priority ladder that governs EVERYTHING the Radio Engine decides.
///
/// Priority is the single most important concept in the engine: when two audio
/// items compete, the higher-priority one wins (plays first / interrupts). The
/// ladder is ordered from most to least urgent. A lower [rank] number means
/// higher priority.
///
/// This enum is the source of truth for ordering the playback queue and for
/// deciding whether an incoming item may interrupt whatever is currently
/// playing.
enum PlaybackPriority {
  emergencyAlert(0),
  safetyWarning(1),
  gpsNarration(2),
  scheduledAnnouncement(3),
  stationIdentification(4),
  music(5),
  ambientAudio(6);

  const PlaybackPriority(this.rank);

  /// Lower = more urgent.
  final int rank;

  /// True if `this` should win over [other].
  bool isHigherThan(PlaybackPriority other) => rank < other.rank;
}
