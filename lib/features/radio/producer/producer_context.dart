import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/producer/producer_enums.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

/// An immutable snapshot of the listener's preferences relevant to production.
///
/// A value snapshot (rather than the mutable `UserPreferenceManager`) keeps the
/// context pure and the Producer deterministic/testable.
class ProducerPreferences {
  const ProducerPreferences({
    this.narrationsEnabled = true,
    this.announcementsEnabled = true,
    this.ambientEnabled = true,
    this.mutedTags = const {},
  });

  final bool narrationsEnabled;
  final bool announcementsEnabled;
  final bool ambientEnabled;
  final Set<String> mutedTags;

  bool allowsTags(List<String> tags) => !tags.any(mutedTags.contains);
}

/// EVERYTHING the Producer evaluates to make one decision.
///
/// This is the single input to [ProducerEngine.determineNextItem]. It bundles
/// the environment (station, GPS, destination/park/state/route, time, weather,
/// season), the listener ([preferences], [recentlyPlayedIds]), the queue state
/// ([queueLength], cadence counters), what is currently playing
/// ([currentSegment]/[hasPausedMusic]), and the candidate segments the Producer
/// may choose from for each priority tier.
///
/// GPS fields ([gpsLocation], [upcomingGpsStories], [upcomingAttraction]) are
/// placeholders wired for the future GPS feature — today they are simply null/
/// empty unless a caller supplies them.
class ProducerContext {
  const ProducerContext({
    required this.now,
    this.station,
    this.gpsLocation,
    this.destinationId,
    this.parkId,
    this.stateName,
    this.routeId,
    this.weather = WeatherCondition.unknown,
    this.season,
    this.timeOfDay,
    this.preferences = const ProducerPreferences(),
    this.recentlyPlayedIds = const [],
    this.upcomingGpsStories = const [],
    this.queueLength = 0,
    this.tracksSinceStory = 0,
    this.tracksSinceStationId = 0,
    this.currentSegment,
    this.hasPausedMusic = false,
    this.pendingEmergency,
    this.pendingSafety,
    this.pendingNavigation,
    this.scheduledStory,
    this.upcomingAttraction,
    this.stationId,
    this.nextMusic,
    this.ambient,
  });

  // --- Environment ---------------------------------------------------------
  final DateTime now;
  final RadioStation? station;
  final GeoPoint? gpsLocation; // placeholder for GPS
  final String? destinationId;
  final String? parkId;
  final String? stateName;
  final String? routeId;
  final WeatherCondition weather; // placeholder
  final Season? season;
  final TimeOfDayBucket? timeOfDay;

  // --- Listener ------------------------------------------------------------
  final ProducerPreferences preferences;
  final List<String> recentlyPlayedIds;

  // --- GPS look-ahead (placeholder) ---------------------------------------
  final List<AudioSegment> upcomingGpsStories;

  // --- Queue / playback state ---------------------------------------------
  final int queueLength;
  final int tracksSinceStory;
  final int tracksSinceStationId;
  final AudioSegment? currentSegment;
  final bool hasPausedMusic;

  // --- Candidate segments per priority tier --------------------------------
  final AudioSegment? pendingEmergency;
  final AudioSegment? pendingSafety;
  final AudioSegment? pendingNavigation;
  final AudioSegment? scheduledStory;
  final AudioSegment? upcomingAttraction; // GPS-ready
  final AudioSegment? stationId;
  final AudioSegment? nextMusic;
  final AudioSegment? ambient;

  /// Resolved (or derived) environment helpers.
  TimeOfDayBucket get resolvedTimeOfDay =>
      timeOfDay ?? TimeOfDayBucket.fromDateTime(now);
  Season get resolvedSeason => season ?? Season.fromDateTime(now);

  /// True when we have any location signal to tailor content (GPS-ready).
  bool get hasLocationContext =>
      gpsLocation != null || parkId != null || stateName != null;
}
