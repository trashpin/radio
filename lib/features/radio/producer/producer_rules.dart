/// Tunable thresholds/toggles that shape the Producer's decisions.
///
/// WHY THIS EXISTS: keeping the "policy knobs" out of the engine logic makes the
/// Producer's behavior configurable per station/product without editing code.
/// Defaults give a sensible radio feel; a station could override cadences.
class ProducerRules {
  const ProducerRules({
    this.storyEveryTracks = 3,
    this.stationIdEveryTracks = 5,
    this.minMusicQueueLength = 2,
    this.enableLocationMusic = true,
    this.respectUserPreferences = true,
    this.allowAmbientWhenIdle = true,
  });

  /// Insert a story after at least this many music tracks.
  final int storyEveryTracks;

  /// Play a station identification after at least this many music tracks.
  final int stationIdEveryTracks;

  /// Keep the queue topped up to at least this many music items.
  final int minMusicQueueLength;

  /// Allow location/context-aware music selection (GPS-ready).
  final bool enableLocationMusic;

  /// Honor the listener's preferences (mute tags, disable ambient, etc.).
  final bool respectUserPreferences;

  /// Play ambient audio when nothing else is eligible.
  final bool allowAmbientWhenIdle;
}
