import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config_repository.dart';
import 'package:explorer_os_mobile/features/around_me/models/experience.dart';
import 'package:explorer_os_mobile/features/around_me/providers/around_me_providers.dart';
import 'package:explorer_os_mobile/features/destinations/data/destination_repository.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/dj_banter_repository.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/banter_moment.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/gps_banter_director.dart';
import 'package:explorer_os_mobile/features/dj/data/dj_clip_repository.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';
import 'package:explorer_os_mobile/features/locations/data/location_narration.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/radio/discovery/community_welcome_director.dart';
import 'package:explorer_os_mobile/features/location_intelligence/location_intelligence.dart';
import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_engine_service.dart';
import 'package:explorer_os_mobile/features/weather/county_radio.dart';
import 'package:explorer_os_mobile/features/weather/current_weather.dart';
import 'package:explorer_os_mobile/features/weather/weather_service.dart';
import 'package:explorer_os_mobile/features/radio_automation/data/radio_automation_repository.dart';
import 'package:explorer_os_mobile/features/radio_automation/services/automation_engine.dart';
import 'package:explorer_os_mobile/features/media/data/media_repository.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/radio/providers/radio_engine_providers.dart';
import 'package:explorer_os_mobile/features/radio/providers/stations_provider.dart';
import 'package:explorer_os_mobile/features/radio/repositories/song_repository.dart';
import 'package:explorer_os_mobile/features/radio/services/background_discovery_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/radio_scheduler.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

/// Bootstraps a listening session: attaches audio output, derives the active
/// station from Base44 content (a destination that has audio `media`), loads
/// that destination's audio playlist, and hands it to the engine WITHOUT
/// auto-playing (the UI's Play button starts it, per web autoplay rules).
///
/// This is the glue that makes the radio audible against the real Base44
/// schema: `destinations` → station, `media` (audio in the `mp3` bucket) →
/// playlist → engine → audio adapter. Returns the active station for the UI;
/// surfaces a friendly error when there is no audio content yet.
final radioSessionProvider = FutureProvider<RadioStation>((ref) async {
  // Attach the audio adapter (engine intent → real sound via just_audio).
  ref.read(radioAudioServiceProvider);

  final engine = ref.read(radioEngineServiceProvider);

  // Feed the Background Discovery Engine with nearby environmental content so
  // the radio can teach about the surroundings during quiet stretches.
  _attachDiscovery(ref, engine);

  // Wire the GPS-aware DJ Banter library so the DJ references the surroundings
  // between songs (defensive no-op when there's no library / GPS yet).
  _attachGpsBanter(ref, engine);

  // Keep a live forecast cached so banter + the county welcome are weather-aware.
  _attachWeather(ref);

  // Welcome the traveler into each new county with a weather + recommendation
  // report (once per county, like a live travel radio station).
  _attachCountyWelcome(ref);

  // Announce approaching communities (~1 mile out) and welcome the traveler
  // into each town/community as they arrive (once per visit).
  _attachCommunityWelcome(ref);

  // Load pre-generated DJ voice clips (from dj_banter_clips) + published
  // Radio Automation library segments that have audio, so the DJ speaks
  // in-character between songs (falls back to TTS when none exist yet).
  try {
    final clips = await ref.read(djClipRepositoryProvider).all();
    final autoRepo = ref.read(radioAutomationRepositoryProvider);
    final segmentClips = await autoRepo.playableClips();
    final all = [...clips, ...segmentClips];
    if (all.isNotEmpty) engine.djBanter.setClips(all);

    // Rule-driven automation: song-boundary triggers run inside the engine's
    // between-song hook; time-based triggers run on this periodic tick.
    final rules = await autoRepo.rules();
    final segments = await autoRepo.segments();
    if (rules.isNotEmpty) {
      engine.djBanter.setAutomation(AutomationEngine(), rules, segments);
      final start = DateTime.now();
      final timer = Timer.periodic(const Duration(seconds: 60), (_) {
        final mins = DateTime.now().difference(start).inMinutes;
        final seg = engine.djBanter.onTick(
          radioStationName: engine.getCurrentStation()?.name,
          sessionMinutes: mins,
        );
        if (seg != null) {
          ref
              .read(radioEngineControllerProvider.notifier)
              .requestInterruption(seg);
        }
      });
      ref.onDispose(timer.cancel);
    }
  } catch (_) {}

  final media = ref.read(mediaRepositoryProvider);

  // If the user picked a station from the Stations screen, honor it; load its
  // audio from the linked destination's media (empty for curated stations
  // until they have content).
  final songRepo = ref.read(songRepositoryProvider);
  final selected = ref.watch(selectedStationProvider);
  if (selected != null) {
    // Prefer dynamic songs uploaded via the admin (songs table), matched by
    // station name; fall back to the linked destination's media, then any
    // active songs so playback always has content.
    var songs = await songRepo.activeSongs(station: selected.name);
    if (songs.isEmpty && selected.destinationId != null) {
      songs = await media.songsForDestination(selected.destinationId!);
    }
    if (songs.isEmpty) songs = await songRepo.activeSongs();
    ref
        .read(radioEngineServiceProvider)
        .changeStation(selected, songs: songs, autoPlay: false);
    ref.read(radioEngineControllerProvider);
    _attachScheduler(ref, selected);
    return selected;
  }

  final destinations = await ref
      .watch(destinationRepositoryProvider)
      .fetchDestinations();
  if (destinations.isEmpty) {
    throw const AppException(
      'No destinations are available yet. Add a destination (and audio media) '
      'in Base44 to start listening.',
      type: AppExceptionType.notFound,
    );
  }

  // Prefer a destination that actually has audio media so the station can play.
  final withAudio = await media.destinationIdsWithAudio();
  final destination = destinations.firstWhere(
    (d) => withAudio.contains(d.id),
    orElse: () => destinations.first,
  );

  final station = RadioStation.fromDestination(destination);
  // Dynamic playlist: prefer admin-uploaded songs (songs table), fall back to
  // the destination's media audio.
  var songs = await songRepo.activeSongs();
  if (songs.isEmpty) songs = await media.songsForDestination(destination.id);

  ref
      .read(radioEngineServiceProvider)
      .changeStation(station, songs: songs, autoPlay: false);

  // Ensure the controller is alive so it reflects engine events in the UI.
  ref.read(radioEngineControllerProvider);
  _attachScheduler(ref, station);

  return station;
});

/// Feeds the Background Discovery scheduler from the Location Intelligence
/// Engine: distance-priority, geocoded, ranked-nearest-first content within
/// ~20 miles — so the radio always teaches about where the visitor is RIGHT
/// NOW and never about a place 100 miles away. Updates continuously as GPS
/// changes; defensive no-op when GPS/content are unavailable.
void _attachDiscovery(Ref ref, RadioEngineService engine) {
  // Location Intelligence caps relevance at 20 miles (the priority-band edge).
  engine.discovery.radiusMeters = 20 * 1609.344;

  void push(LocationContext ctx) {
    final candidates = <DiscoveryCandidate>[];
    for (final r in ctx.nearby) {
      final category = _discoveryCategoryFor(r.item.category);
      if (category == null) continue;
      final desc = (r.item.text ?? '').trim();
      candidates.add(
        DiscoveryCandidate(
          id: r.item.id,
          category: category,
          title: r.item.title,
          distanceMeters: r.distanceMeters,
          audioUrl: r.item.audioUrl,
          spokenText: desc.isEmpty
              ? "You're near ${r.item.title}."
              : "You're near ${r.item.title}. $desc",
        ),
      );
    }
    engine.discovery.updateNearby(candidates);
  }

  try {
    push(ref.read(locationContextProvider));
  } catch (_) {}
  ref.listen<LocationContext>(locationContextProvider, (_, next) => push(next));
}

/// Maps a rich [ContentCategory] to the discovery scheduler's smaller taxonomy
/// (null = not a "teach the environment" topic).
DiscoveryCategory? _discoveryCategoryFor(ContentCategory c) {
  switch (c) {
    case ContentCategory.wildlife:
      return DiscoveryCategory.wildlife;
    case ContentCategory.plants:
      return DiscoveryCategory.plants;
    case ContentCategory.birds:
      return DiscoveryCategory.birds;
    case ContentCategory.trees:
      return DiscoveryCategory.trees;
    case ContentCategory.water:
    case ContentCategory.riverStory:
    case ContentCategory.lakeStory:
      return DiscoveryCategory.geology;
    case ContentCategory.forestStory:
      return DiscoveryCategory.trees;
    // Area stories — county / city / community / historic — air as spoken
    // "where you are" narration (mapped to the discovery taxonomy).
    case ContentCategory.welcome:
    case ContentCategory.countyWelcome:
    case ContentCategory.countyHistory:
    case ContentCategory.cityWelcome:
    case ContentCategory.cityHistory:
    case ContentCategory.cityIntro:
    case ContentCategory.communityStory:
    case ContentCategory.historicHighway:
    case ContentCategory.historicLandmark:
    case ContentCategory.history:
    case ContentCategory.parkStory:
    case ContentCategory.arrival:
      return DiscoveryCategory.history;
    case ContentCategory.countyFunFacts:
    case ContentCategory.cityFunFacts:
    case ContentCategory.countyAgriculture:
    case ContentCategory.countyEconomy:
    case ContentCategory.interestingFact:
      return DiscoveryCategory.interestingFact;
    case ContentCategory.countyNature:
      return DiscoveryCategory.wildlife;
    case ContentCategory.countyHiddenGems:
    case ContentCategory.hiddenGem:
    case ContentCategory.scenicOverlook:
    case ContentCategory.scenicDrive:
      return DiscoveryCategory.hiddenGem;
    default:
      return null;
  }
}

/// Wires the GPS-Aware DJ Banter Studio library into the live radio: loads the
/// published clips and gives the DJ banter scheduler a director + a live GPS
/// context supplier + a play recorder. The scheduler prefers these per-
/// destination, GPS-aware lines between songs (never repeating within a trip),
/// falling back to template banter when the library is empty.
void _attachGpsBanter(Ref ref, RadioEngineService engine) {
  final repo = ref.read(djBanterRepositoryProvider);
  engine.djBanter.setGpsBanter(
    director: GpsBanterDirector(),
    trip: BanterTrip(),
    context: () => _banterContext(ref, engine),
    onPlayed: (id) => repo.recordPlay(id),
  );
  // Load the published library once (the director filters by location context);
  // reload as the visitor's surroundings change is unnecessary since matching
  // is done per-pick against the live context.
  Future<void> load() async {
    try {
      engine.djBanter.setBanterLibrary(await repo.publishedFor());
    } catch (_) {}
  }

  load();
}

/// Refreshes the shared current-forecast cache whenever the visitor's location
/// context changes (throttled inside [CurrentWeather]).
void _attachWeather(Ref ref) {
  void refresh() {
    final c = ref.read(mapCenterProvider);
    final g = ref.read(gpsControllerProvider).location;
    final lat = c?.latitude ?? g?.latitude;
    final lng = c?.longitude ?? g?.longitude;
    if (lat != null && lng != null) {
      ref.read(currentWeatherProvider.notifier).refresh(lat, lng);
    }
  }

  refresh();
  ref.listen<LocationContext>(locationContextProvider, (_, _) => refresh());
}

/// Welcomes the traveler into each new county: on a county change, fetches the
/// current weather and plays a spoken Station ID → Welcome → Weather →
/// Recommendation report through the radio's interrupt→resume path (music
/// resumes at the exact spot). Once per county per session.
void _attachCountyWelcome(Ref ref) {
  final director = CountyWelcomeDirector();
  final weather = ref.read(weatherClientProvider);
  var busy = false;

  Future<void> maybeWelcome(LocationContext ctx) async {
    final county = ctx.county;
    if (county == null || county.trim().isEmpty) return;
    if (busy || director.hasWelcomed(county)) return;
    busy = true;
    try {
      final center = ref.read(mapCenterProvider);
      final loc = ref.read(gpsControllerProvider).location;
      final lat = center?.latitude ?? loc?.latitude;
      final lng = center?.longitude ?? loc?.longitude;
      // Prefer the shared cached forecast; fetch directly only if it's empty.
      var w = ref.read(currentWeatherProvider);
      if (w == null && lat != null && lng != null) {
        w = await weather.fetch(lat, lng);
      }
      final greetings = ref.read(countyGreetingsProvider);
      final script = director.scriptFor(
        county,
        ctx.state,
        w,
        greetings: greetings,
      );
      if (script == null) return;
      ref
          .read(radioEngineControllerProvider.notifier)
          .requestInterruption(
            AudioSegment(
              id:
                  'county:${county.toLowerCase()}'
                  ':${DateTime.now().millisecondsSinceEpoch}',
              title: 'Welcome to $county County',
              type: AudioSegmentType.gpsNarration,
              priority: PlaybackPriority.scheduledAnnouncement,
              spokenText: script,
              interruptible: true,
              resumeAfter: true,
            ),
          );
    } catch (_) {
      // Never let a weather/network hiccup break the session.
    } finally {
      busy = false;
    }
  }

  maybeWelcome(ref.read(locationContextProvider));
  ref.listen<LocationContext>(locationContextProvider, (prev, next) {
    if ((prev?.county ?? '').toLowerCase() !=
        (next.county ?? '').toLowerCase()) {
      // Leaving a county re-arms its welcome so returning later replays it
      // ("only once until you leave the county").
      director.leftCounty(prev?.county);
      maybeWelcome(next);
    }
  });
}

/// Level 2 — Communities. Announces "in about a mile you'll be entering …" as
/// the traveler approaches a town/community (from the master `locations` table,
/// type community/city), then fades the music and welcomes them on arrival —
/// each at most once per visit, replaying on a later return. Reuses the radio
/// engine's interrupt→resume path (same as the county welcome).
void _attachCommunityWelcome(Ref ref) {
  final director = CommunityWelcomeDirector();

  List<CommunityPlace> communities() {
    final all = ref.read(masterLocationsProvider).value ?? const [];
    final out = <CommunityPlace>[];
    for (final l in all) {
      if (l.type != LocationType.community && l.type != LocationType.city) {
        continue;
      }
      if (!l.active || l.hidden || !l.hasCoordinates) continue;
      out.add(
        CommunityPlace(
          id: l.id,
          name: l.name,
          latitude: l.latitude!,
          longitude: l.longitude!,
          entryRadiusMeters: l.triggerRadius,
        ),
      );
    }
    return out;
  }

  MasterLocation? locById(String id) {
    for (final l in ref.read(masterLocationsProvider).value ?? const []) {
      if (l.id == id) return l;
    }
    return null;
  }

  void evaluateAndPlay(LocationContext ctx) {
    if (ctx.latitude == 0 && ctx.longitude == 0) return; // no GPS fix yet
    final list = communities();
    if (list.isEmpty) return;
    final cue = director.evaluate(ctx.latitude, ctx.longitude, list);
    if (cue == null) return;

    final radio = ref.read(radioEngineControllerProvider.notifier);
    final ts = DateTime.now().millisecondsSinceEpoch;
    if (cue.kind == CommunityCueKind.approach) {
      radio.requestInterruption(
        AudioSegment(
          id: 'community-approach:${cue.place.id}:$ts',
          title: 'Approaching ${cue.place.name}',
          type: AudioSegmentType.gpsNarration,
          priority: PlaybackPriority.scheduledAnnouncement,
          spokenText: CommunityWelcomeDirector.approachScript(cue.place.name),
          interruptible: true,
          resumeAfter: true,
        ),
      );
    } else {
      // Entry welcome: prefer the community's recorded narration, else speak a
      // composed script (falls back to a simple "Welcome to …").
      final loc = locById(cue.place.id);
      final narration = loc == null
          ? null
          : resolveLocationNarration(
              loc,
              ref.read(locationContentItemsProvider),
            );
      final hasAudio = narration?.hasAudio ?? false;
      final text = (narration?.text.trim().isNotEmpty ?? false)
          ? narration!.text.trim()
          : CommunityWelcomeDirector.entryFallbackScript(cue.place.name);
      radio.requestInterruption(
        AudioSegment(
          id: 'community-entry:${cue.place.id}:$ts',
          title: 'Welcome to ${cue.place.name}',
          type: AudioSegmentType.narration,
          priority: PlaybackPriority.scheduledAnnouncement,
          audioUrl: hasAudio ? narration!.audioUrl : null,
          spokenText: hasAudio ? null : text,
          interruptible: true,
          resumeAfter: true,
        ),
      );
    }
  }

  // Guarded so a community-detection hiccup can never break the radio session.
  void handle(LocationContext ctx) {
    try {
      evaluateAndPlay(ctx);
    } catch (_) {}
  }

  handle(ref.read(locationContextProvider));
  ref.listen<LocationContext>(
    locationContextProvider,
    (_, next) => handle(next),
  );
}

bool _hasWord(String c, List<String> words) => words.any(c.contains);

/// Builds the live [GpsBanterContext] from the GPS engine + Around Me feed at
/// the moment the DJ is about to speak, so `{placeholders}` resolve to the
/// visitor's actual surroundings.
GpsBanterContext _banterContext(Ref ref, RadioEngineService engine) {
  final t = ref.read(gpsControllerProvider);
  final w = ref.read(currentWeatherProvider);
  List<Experience> exps;
  try {
    exps = ref.read(aroundMeExperiencesProvider);
  } catch (_) {
    exps = const [];
  }
  List<String> named(List<String> words) => [
    for (final e in exps)
      if (_hasWord(e.category.toLowerCase(), words)) e.name,
  ].take(3).toList();

  final stationName = engine.getCurrentStation()?.name;
  final park = t.currentParkId ?? stationName?.replaceAll(' Radio', '');
  final upcoming =
      t.nextAttraction?.name ??
      t.nearestAttraction?.name ??
      (exps.isNotEmpty ? exps.first.name : null);

  return GpsBanterContext(
    latitude: t.location?.latitude,
    longitude: t.location?.longitude,
    park: park,
    county: t.currentCounty,
    road: t.currentRoad,
    upcomingAttraction: upcoming,
    nearbyWildlife: named([
      'wildlife',
      'animal',
      'mammal',
      'bear',
      'gator',
      'deer',
    ]),
    nearbySprings: named(['spring']),
    nearbyRivers: named(['river', 'creek']),
    nearbyLakes: named(['lake']),
    nearbyTrails: named(['trail']),
    nearbyHistoricSites: named(['histor', 'fort', 'heritage']),
    station: stationName ?? 'Explorer Radio',
    // Time-of-day + season + live-weather aware banter.
    moment: BanterMoment.now(
      weatherCondition: w?.condition,
      tempF: w?.temperatureF ?? w?.highF,
    ),
  );
}

/// Starts the programming scheduler for the session: it injects due
/// announcements (safety/wildlife with audio) into the engine's interruption
/// path. No-op until `radio_schedule` rules + voiceover audio exist.
void _attachScheduler(Ref ref, RadioStation station) {
  final scheduler = ref.read(radioSchedulerProvider);
  scheduler.start(station: station.name);
  ref.onDispose(scheduler.stop);
}

/// The programming scheduler (singleton). Exposed so the radio UI can trigger a
/// "Test announcement" (fireNow) and so the session can start/stop it.
final radioSchedulerProvider = Provider<RadioScheduler>((ref) {
  return RadioScheduler(
    client: SupabaseService.isConfigured ? SupabaseService.client : null,
    inject: (seg) => ref
        .read(radioEngineControllerProvider.notifier)
        .requestInterruption(seg),
  );
});
