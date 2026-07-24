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
  static const String gpsAudioTriggers = 'gps_audio_triggers';

  // User-owned data (writable, synced per user).
  static const String userFavorites = 'user_favorites';
  static const String downloads = 'downloads';
}
