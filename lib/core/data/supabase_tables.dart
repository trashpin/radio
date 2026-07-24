/// Canonical Supabase table names for every ExplorerOS entity.
///
/// Centralizing table names (instead of sprinkling string literals through
/// repositories) prevents typos and makes a rename a one-line change. These are
/// the single source of truth referenced by every repository.
class SupabaseTables {
  const SupabaseTables._();

  // Read-only destination content.
  static const String destinations = 'destinations';
  static const String parks = 'parks';
  static const String stops = 'stops';
  static const String stories = 'stories';
  static const String wildlife = 'wildlife';
  static const String plants = 'plants';
  static const String radioStations = 'radio_stations';
  static const String songs = 'songs';
  static const String narrations = 'narrations';
  static const String announcements = 'announcements';
  static const String stationRules = 'station_rules';
  static const String stationProfiles = 'station_profiles';
  static const String gpsAudioTriggers = 'gps_audio_triggers';
  static const String playbackHistory = 'playback_history';
  static const String parkBoundaries = 'park_boundaries';
  static const String stateBoundaries = 'state_boundaries';
  static const String countyBoundaries = 'county_boundaries';
  static const String locationHistory = 'location_history';
  static const String travelSessions = 'travel_sessions';

  // Music library.
  static const String albums = 'albums';
  static const String genres = 'genres';
  static const String moods = 'moods';
  static const String artworks = 'artworks';
  static const String musicMetadata = 'music_metadata';
  static const String playlists = 'playlists';
  static const String stationAssignments = 'station_assignments';
  static const String gpsMusicTriggers = 'gps_music_triggers';
  static const String uploadJobs = 'upload_jobs';

  // User-owned data (writable, synced per user).
  static const String userFavorites = 'user_favorites';
  static const String downloads = 'downloads';
}
