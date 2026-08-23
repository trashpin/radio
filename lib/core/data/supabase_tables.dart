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

  /// Base44 AI Ranger knowledge articles (linked to destinations/stops).
  static const String knowledgeArticles = 'knowledge_articles';

  /// Master natural-history catalog (plants, trees, birds, mammals, …).
  static const String species = 'species';

  /// Geolocated points (all categories) for the real-time "Around Me" map.
  static const String mapLocations = 'map_locations';

  /// Base44 media table (audio/photo/video). Audio rows (`file_url` in the
  /// `mp3` bucket) are the real source for Explorer Radio playback.
  static const String media = 'media';
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

  /// Ocala Forest Explorer — an isolated experimental feature, stored
  /// separately from `locations`/`county_boundaries`/`park_boundaries`.
  static const String forestBoundaries = 'forest_boundaries';
  static const String forestLocations = 'forest_locations';
  static const String forestTrailSegments = 'forest_trail_segments';
  static const String forestTrails = 'forest_trails';

  /// `forest_trails` plus a `geom_geojson` text column — reads real PostGIS
  /// trail geometry as plain GeoJSON text over PostgREST.
  static const String forestTrailsWithGeojson = 'forest_trails_with_geojson';

  /// DISCOVER (spec: community photo-identified discoveries). The base
  /// table (writes go here) has no anon/authenticated SELECT policy at all
  /// — every public read must go through the `_public` view below, which
  /// generalizes sensitive-location coordinates server-side.
  static const String forestDiscoveryReports = 'forest_discovery_reports';
  static const String forestDiscoveryReportsPublic = 'forest_discovery_reports_public';

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

  /// Citizen-science observations from "I See Something".
  static const String explorerSightings = 'explorer_sightings';
}
