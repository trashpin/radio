import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/features/discover_area/data/area_content_repository.dart';
import 'package:explorer_os_mobile/features/discover_area/models/area_content_block.dart';
import 'package:explorer_os_mobile/features/gps/data/geofence_repository.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config_repository.dart';
import 'package:explorer_os_mobile/features/around_me/models/experience.dart';
import 'package:explorer_os_mobile/features/around_me/providers/around_me_providers.dart';
import 'package:explorer_os_mobile/features/destinations/data/destination_repository.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/dj_banter_repository.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/banter_moment.dart';
import 'package:explorer_os_mobile/features/dj/banter_studio/gps_banter_director.dart';
import 'package:explorer_os_mobile/features/dj/data/dj_clip_repository.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/services/location_trigger_engine.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';
import 'package:explorer_os_mobile/features/locations/active_location_types.dart';
import 'package:explorer_os_mobile/features/locations/data/location_narration.dart';
import 'package:explorer_os_mobile/features/radio_automation/services/announcement_content.dart';
import 'package:explorer_os_mobile/features/radio/banter/location_banter_scheduler.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/radio/discovery/community_welcome_director.dart';
import 'package:explorer_os_mobile/features/location_intelligence/location_intelligence.dart';
import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/radio/data/explore_play_history.dart';
import 'package:explorer_os_mobile/features/radio/events/radio_event.dart';
import 'package:explorer_os_mobile/features/radio/models/audio_segment.dart';
import 'package:explorer_os_mobile/features/radio/models/playback_priority.dart';
import 'package:explorer_os_mobile/features/radio/providers/explore_providers.dart';
import 'package:explorer_os_mobile/features/radio/services/explore_rotation_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/player_location_context.dart';
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

  // Wire the Radio Banter Engine: mix short LOCAL narration (park > city >
  // county, e.g. Marion) between songs, reusing each location's own AI content.
  _attachLocationBanter(ref, engine);

  // Feed the DJ admin-authored county facts (CountyConfig.facts) so it can drop
  // real local knowledge between songs; refreshes as the county changes.
  _attachCountyDjFacts(ref, engine);

  // Keep a live forecast cached so banter + the county welcome are weather-aware.
  _attachWeather(ref);

  // Welcome the traveler into each new county with a weather + recommendation
  // report (once per county, like a live travel radio station).
  _attachCountyWelcome(ref);

  // Announce approaching communities (~1 mile out) and welcome the traveler
  // into each town/community as they arrive (once per visit).
  _attachCommunityWelcome(ref);

  // Points of Interest — every OTHER location type (springs, museums, trails,
  // parks, hidden gems, attractions, etc.) gets a generic GPS arrival/
  // departure trigger honoring its own arrival_trigger, departure_trigger,
  // play_once, and cooldown_seconds (migration 0040). County/city/community
  // stay owned by the directors above so nothing double-fires.
  _attachLocationTriggers(ref);

  // MARION COUNTY EXPLORE: pushes the existing-content candidate pool into the
  // engine's Explore rotation and toggles it on/off with the traveler's mode
  // switch + Marion County GPS gate. Sits alongside every director above —
  // Radio mode is completely untouched.
  _attachExplore(ref, engine);

  // GPS-triggered location radio from the Supabase `geofences` table: on each
  // GPS update, ask `get_nearby_geofences()` what the traveler is inside, feed
  // it through the SAME LocationTriggerEngine (enter/exit/cooldown/play-once)
  // used above, resolve the winning location's existing content, and interrupt
  // the radio via the existing engine. Wildlife stays area-based (untouched).
  _attachGeofenceTriggers(ref);

  // Load pre-generated DJ voice clips (from dj_banter_clips) + published
  // Radio Automation library segments that have audio, so the DJ speaks
  // in-character between songs (falls back to TTS when none exist yet).
  try {
    final clips = await ref.read(djClipRepositoryProvider).all();
    final autoRepo = ref.read(radioAutomationRepositoryProvider);
    final segmentClips = await autoRepo.playableClips();
    final all = [...clips, ...segmentClips];
    if (all.isNotEmpty) engine.djBanter.setClips(all);

    // Rule-driven automation (Scheduler Reconciliation, Step 2): ONE engine now
    // drives all non-music announcements. It reads the UNIFIED rule set
    // (radio_schedule_rules + adapted legacy radio_schedule interval rules) and
    // the UNIFIED content pool (radio_segments + safety/wildlife/story), so the
    // safety/wildlife/story announcements formerly driven by RadioScheduler's
    // own timer now run here. Song-boundary triggers run in the between-song
    // hook; time-based triggers run on this single periodic tick.
    final rules = await ref.read(unifiedAutomationRulesProvider.future);
    final segments = await ref.read(unifiedAnnouncementContentProvider.future);
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
    // Announcements (safety/wildlife/story) are now driven by the unified
    // automation tick above — no separate RadioScheduler timer (Step 2).
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
  // Announcements are driven by the unified automation tick above (Step 2).

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
/// Configures the Radio Banter Engine with the live position + master
/// locations, and a resolver that reuses each location's EXISTING content for
/// the clip (recorded audio → AI narration script → composed narration). The
/// engine (park > city > county priority + cooldown + county fallback) then
/// decides which one speaks between songs.
void _attachLocationBanter(Ref ref, RadioEngineService engine) {
  final scheduler = engine.locationBanter;
  if (scheduler == null) return;
  scheduler.configure(context: () {
    final center = ref.read(mapCenterProvider);
    if (center == null) return null;
    final all = ref.read(masterLocationsProvider).value ?? const [];
    if (all.isEmpty) return null;
    final county = ref.read(locationContextProvider).county;
    final content = ref.read(locationContentItemsProvider);
    return BanterRuntime(
      lat: center.latitude,
      lng: center.longitude,
      county: county,
      locations: all,
      resolve: (loc) {
        if (loc.audioFiles.any((u) => u.trim().isNotEmpty)) {
          return BanterClip(audioUrl: loc.audioFiles.first);
        }
        final script = (loc.narrationScript ?? '').trim();
        if (script.isNotEmpty) return BanterClip(text: script);
        final n = resolveLocationNarration(loc, content);
        return n.hasAudio
            ? BanterClip(audioUrl: n.audioUrl, text: n.text)
            : BanterClip(text: n.text);
      },
    );
  });
}

/// Keeps the DJ's county fact pool in sync with the current county's
/// CountyConfig (Admin → County Manager). The DJ then occasionally shares one
/// of those admin-authored facts between songs — see [DjBanterScheduler].
void _attachCountyDjFacts(Ref ref, RadioEngineService engine) {
  void update(String? county) {
    final configs =
        ref.read(countyConfigsProvider).value ?? const <CountyConfig>[];
    final key = (county ?? '').toLowerCase().trim();
    CountyConfig? cfg;
    for (final c in configs) {
      if (c.key == key) {
        cfg = c;
        break;
      }
    }
    engine.djBanter
        .setCountyFacts(county: cfg?.name ?? county, facts: cfg?.facts ?? const []);
    // Phase C: bias music selection toward the county's preferred genres.
    engine.station.setCountyMusicCategories(cfg?.musicCategories ?? const []);
  }

  update(ref.read(locationContextProvider).county);
  ref.listen<LocationContext>(locationContextProvider, (prev, next) {
    if ((prev?.county ?? '').toLowerCase() != (next.county ?? '').toLowerCase()) {
      update(next.county);
    }
  });
  // Also refresh once the admin county configs finish loading / change.
  ref.listen(countyConfigsProvider,
      (_, _) => update(ref.read(locationContextProvider).county));
}

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
      // The full CountyConfig for this county is the single source of truth for
      // its radio personality: whether the weather line / recommendation plays,
      // and its own recommendation list (blended into the weather pool). Falls
      // back to the built-in defaults when there's no admin row yet.
      final configs =
          ref.read(countyConfigsProvider).value ?? const <CountyConfig>[];
      final key = county.toLowerCase().trim();
      CountyConfig? cfg;
      for (final c in configs) {
        if (c.key == key) {
          cfg = c;
          break;
        }
      }
      final script = director.scriptFor(
        county,
        ctx.state,
        w,
        greetings: greetings,
        weatherEnabled: cfg?.weatherEnabled ?? true,
        recommendationsEnabled: cfg?.recommendationsEnabled ?? true,
        recommendations: cfg?.recommendations ?? const [],
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
      if (l.isPublishBlocked) continue;
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

/// Level 3 — Points of Interest. Generic GPS arrival/departure triggers for
/// every master location EXCEPT county/city/community (those have their own
/// directors above, so nothing double-fires). Honors each location's own
/// arrival_trigger, departure_trigger, play_once, and cooldown_seconds
/// (migration 0040) via [LocationTriggerEngine] — a location with no
/// `trigger_radius` set simply never participates (opt-in, same as today).
void _attachLocationTriggers(Ref ref) {
  final engine = LocationTriggerEngine();

  List<TriggerableLocation> candidates() {
    final all = ref.read(masterLocationsProvider).value ?? const [];
    final out = <TriggerableLocation>[];
    for (final l in all) {
      // Only the active tiers may trigger narration today; of those, the
      // county/city/community tiers are owned by the welcome directors, so POI
      // triggers cover just parks / state parks / springs.
      if (!isActiveLocationType(l.type)) continue;
      if (l.type == LocationType.county ||
          l.type == LocationType.city ||
          l.type == LocationType.town ||
          l.type == LocationType.village ||
          l.type == LocationType.community ||
          l.type == LocationType.neighborhood) {
        continue; // owned by the county/community welcome directors
      }
      if (!l.active || l.hidden || !l.hasCoordinates) continue;
      if (l.isPublishBlocked) continue;
      if (l.triggerRadius == null) continue;
      out.add(
        TriggerableLocation(
          id: l.id,
          latitude: l.latitude!,
          longitude: l.longitude!,
          radiusMeters: l.triggerRadius!,
          arrivalTrigger: l.arrivalTrigger,
          departureTrigger: l.departureTrigger,
          playOnce: l.playOnce,
          cooldownSeconds: l.cooldownSeconds,
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

  void fire(LocationTriggerEvent event) {
    final loc = locById(event.locationId);
    if (loc == null) return;
    final radio = ref.read(radioEngineControllerProvider.notifier);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final isArrival = event.kind == LocationTriggerKind.arrival;

    // Departure has no dedicated narration content today — only arrival
    // reuses the location's recorded/generated narration.
    final narration = isArrival
        ? resolveLocationNarration(loc, ref.read(locationContentItemsProvider))
        : null;
    final hasAudio = narration?.hasAudio ?? false;
    final fallback =
        isArrival ? 'Welcome to ${loc.name}.' : "You're leaving ${loc.name}.";
    final text = (narration?.text.trim().isNotEmpty ?? false)
        ? narration!.text.trim()
        : fallback;

    radio.requestInterruption(
      AudioSegment(
        id: 'location-${event.kind.name}:${loc.id}:$ts',
        title: isArrival ? 'Arriving at ${loc.name}' : 'Leaving ${loc.name}',
        type: AudioSegmentType.narration,
        priority: PlaybackPriority.scheduledAnnouncement,
        audioUrl: hasAudio ? narration!.audioUrl : null,
        spokenText: hasAudio ? null : text,
        interruptible: true,
        resumeAfter: true,
      ),
    );
  }

  // Guarded so a location-trigger hiccup can never break the radio session.
  void handle(LocationContext ctx) {
    if (ctx.latitude == 0 && ctx.longitude == 0) return; // no GPS fix yet
    try {
      final events =
          engine.evaluate(ctx.latitude, ctx.longitude, candidates());
      for (final e in events) {
        fire(e);
      }
    } catch (_) {}
  }

  handle(ref.read(locationContextProvider));
  ref.listen<LocationContext>(
    locationContextProvider,
    (_, next) => handle(next),
  );
}

/// Wires MARION COUNTY EXPLORE into the live radio, entirely on top of
/// existing systems:
///  - keeps [RadioEngineService.explore]'s candidate pool in sync with
///    [exploreCandidatesProvider] (existing `location_content`,
///    `destination_narrations`, `counties`, `species`, and the master
///    `locations` table — no new content source);
///  - flips [RadioEngineService.exploreMode] with [exploreActiveProvider]
///    (the traveler's toggle AND the existing GPS county signal being
///    "Marion" — never generates Explore content outside Marion, spec
///    section 1);
///  - checks, on every GPS update, whether WHERE YOU'RE HEADED has become
///    close enough to jump the rotation (spec section 7), reusing the
///    existing [TravelContext.nextAttraction] distance/ETA the GPS engine
///    already computes as the "worth interrupting for" signal, and firing it
///    through the SAME `requestInterruption` path every other director uses;
///  - loads previously-played content IDs from disk (fire-and-forget, same
///    as every other SharedPreferences-backed preference in this app — see
///    [StationPreference] — never gating app/radio startup on disk I/O) and
///    persists them again after every segment Explore actually plays, so a
///    story already heard doesn't repeat just because the app was closed and
///    reopened. [ExploreRotationScheduler] itself stays pure/synchronous —
///    all the I/O lives here.
void _attachExplore(Ref ref, RadioEngineService engine) {
  final history = ref.read(explorePlayHistoryStoreProvider);
  history.load().then(engine.explore.restorePlayed);

  void pushCandidates() {
    engine.explore.updateCandidates(ref.read(exploreCandidatesProvider));
  }

  pushCandidates();
  ref.listen(exploreCandidatesProvider, (_, _) => pushCandidates());

  // Fire-and-forget: persist the updated played-history snapshot every time
  // Explore actually schedules something. By the time SegmentStarted fires,
  // the scheduler has already marked the pick played, so the snapshot here
  // is already current — no need to parse AudioSegment.id (which itself
  // contains colons and would be ambiguous to split).
  engine.events.listen((event) {
    if (event is SegmentStarted && event.segment.tags.contains('explore')) {
      history.save(engine.explore.snapshotPlayed());
    }
  });

  void syncMode() {
    engine.setExploreMode(ref.read(exploreActiveProvider));
  }

  syncMode();
  ref.listen(exploreActiveProvider, (_, _) => syncMode());

  void checkUrgent() {
    if (!ref.read(exploreActiveProvider)) return;
    // Reads distance/ETA straight off Explore's OWN ahead-of-travel
    // candidates (not gpsControllerProvider.nextAttraction, a separate
    // candidate pool that in production is never populated) so the
    // "close enough to interrupt for" check and the candidate actually
    // narrated are always about the same place.
    final pool = ref.read(exploreCandidatesProvider);
    final ahead = <ExploreCandidate>[
      ...?pool[ExploreCategory.whereHeaded],
      ...?pool[ExploreCategory.events],
    ]..sort((a, b) => (a.distanceMeters ?? double.infinity)
        .compareTo(b.distanceMeters ?? double.infinity));
    if (ahead.isEmpty) return;
    final nearest = ahead.first;
    final closeEnough = (nearest.distanceMeters != null &&
            nearest.distanceMeters! <= 1609.344) ||
        (nearest.eta != null && nearest.eta! <= const Duration(minutes: 3));
    final seg = engine.explore.urgent(nearest, isCloseEnough: closeEnough);
    if (seg != null) {
      ref.read(radioEngineControllerProvider.notifier).requestInterruption(seg);
    }
  }

  // Explore is discovery-first, not music-first (spec): a fresh session
  // should open with a personalized greeting before local discovery, never a
  // plain song — GPS LOCATION -> DETERMINE TOWN/CITY -> TIME-OF-DAY GREETING
  // -> BEGIN LOCAL EXPLORE CONTENT, regardless of whether the traveler is
  // moving or stationary. Pushes the place name RadioEngineService._takeNext
  // needs for its cold-start check — reuses the SAME place-name resolution
  // (playerLocationContextProvider.title) _whereYouAreCandidate already
  // reads elsewhere — no new GPS/geocoding work.
  void syncGpsDerivedExploreFields() {
    engine.currentPlaceName = ref.read(playerLocationContextProvider)?.title;
  }

  syncGpsDerivedExploreFields();
  checkUrgent();
  ref.listen(gpsControllerProvider, (_, _) {
    syncGpsDerivedExploreFields();
    checkUrgent();
  });
}

// --- GPS geofence → radio (Supabase `geofences` + get_nearby_geofences) ------

/// Builds [TriggerableLocation]s that feed the reused [LocationTriggerEngine]
/// the geofence membership decided by `get_nearby_geofences()`. We do NOT
/// recompute geodesic distance here (the DB already did): an "inside" fence is
/// anchored at the user's position (distance 0 ≤ radius → inside) and a fence
/// that was inside last tick but isn't now is anchored ~111 km away (→ outside),
/// so the engine emits the correct enter/exit transitions and still honors
/// play-once + cooldown. Pure + testable.
List<TriggerableLocation> geofenceTriggerCandidates({
  required Set<String> insideIds,
  required Set<String> recentIds,
  required double userLat,
  required double userLng,
  int? Function(String locationId)? cooldownForLocation,
  bool Function(String locationId)? playOnceForLocation,
}) {
  const anchorRadius = 1000.0;
  final farLat = (userLat + 1.0).clamp(-89.0, 89.0); // ~111 km away → outside
  final ids = {...insideIds, ...recentIds};
  return [
    for (final id in ids)
      TriggerableLocation(
        id: id,
        latitude: insideIds.contains(id) ? userLat : farLat,
        longitude: userLng,
        radiusMeters: anchorRadius,
        arrivalTrigger: true,
        departureTrigger: false, // geofence ENTER narrates; exit has no content
        // Previously hardcoded false, ignoring the location's own play_once
        // setting entirely — a location an admin marked play-once could still
        // re-narrate every time the geofence was re-entered.
        playOnce: playOnceForLocation?.call(id) ?? false,
        cooldownSeconds: cooldownForLocation?.call(id),
      ),
  ];
}

/// Picks the single geofence to narrate from the fences the traveler just
/// ENTERED this tick — highest priority (priority_override) first, then the
/// closest — so multiple competing location narrations never fire at once.
NearbyGeofence? selectGeofenceToNarrate(Iterable<NearbyGeofence> entered) {
  NearbyGeofence? best;
  for (final g in entered) {
    if (best == null ||
        g.priority > best.priority ||
        (g.priority == best.priority &&
            g.distanceMeters < best.distanceMeters)) {
      best = g;
    }
  }
  return best;
}

/// Resolves a geofence ENTER into a playable [AudioSegment] using EXISTING
/// content, or null when there's nothing to say (caller logs + skips):
///   1. the location's own `area_discovery_content` (active, non-wildlife);
///   2. else [resolveLocationNarration] (the location's audio / matched
///      `location_content` / a composed TTS script).
/// Wildlife blocks are intentionally skipped so wildlife stays area-based.
AudioSegment? geofenceSegmentFor({
  required String locationId,
  required String locationName,
  required List<AreaContentBlock> areaBlocks,
  MasterLocation? masterLocation,
  List<ContentItem> contentItems = const [],
}) {
  String? title;
  String? audioUrl;
  String? script;

  for (final b in areaBlocks) {
    if (!b.active || !b.hasNarration) continue;
    if (_isWildlifeToken(b.categoryToken)) continue; // wildlife stays separate
    title = b.title.trim().isNotEmpty ? b.title.trim() : locationName;
    if (b.hasAudio) {
      audioUrl = b.audioUrl;
    } else {
      script = b.narrationScript;
    }
    break;
  }

  if (title == null && masterLocation != null) {
    final n = resolveLocationNarration(masterLocation, contentItems);
    if (n.hasAudio) {
      title = n.title;
      audioUrl = n.audioUrl;
    } else if (n.text.trim().isNotEmpty) {
      title = n.title;
      script = n.text.trim();
    }
  }

  if (title == null || (audioUrl == null && (script ?? '').trim().isEmpty)) {
    return null;
  }

  return AudioSegment(
    id: 'geofence:$locationId:${DateTime.now().millisecondsSinceEpoch}',
    title: title,
    type: AudioSegmentType.gpsNarration,
    priority: PlaybackPriority.scheduledAnnouncement,
    audioUrl: audioUrl,
    spokenText: audioUrl == null ? script : null,
    interruptible: true,
    resumeAfter: true,
  );
}

bool _isWildlifeToken(String token) {
  final t = token.toLowerCase();
  const keys = [
    'wildlife', 'animal', 'bird', 'mammal', 'reptile', 'fish',
    'wildflower', 'native_plant', 'plant', 'tree', 'species',
  ];
  return keys.any(t.contains);
}

/// Carries the "inside last tick" set between [geofenceRadioTick] calls, so the
/// engine can see a fence go from inside → outside (and fire the exit that
/// re-arms a later re-entry) without recomputing any geodesic distance.
class GeofenceTickState {
  Set<String> insidePrev = <String>{};
}

/// One geofence-radio tick, pure of Riverpod + audio so it is fully testable:
///  1. asks [fetchNearby] (→ `get_nearby_geofences`) what fences the traveler
///     is inside,
///  2. feeds that membership through the reused [engine] (enter/exit/cooldown),
///  3. picks the winner (priority → distance),
///  4. resolves the winner's EXISTING content ([fetchBlocks] →
///     `area_discovery_content`, else [resolveLocationNarration]),
/// and RETURNS the [AudioSegment] to interrupt with (or null when there is
/// nothing to say). Emits the `[GEOFENCE RADIO]` diagnostics. The caller sends
/// the result through the existing RadioEngineService — this never touches the
/// audio core.
Future<AudioSegment?> geofenceRadioTick({
  required double lat,
  required double lng,
  required LocationTriggerEngine engine,
  required GeofenceTickState state,
  required Future<List<NearbyGeofence>> Function(double lat, double lng)
      fetchNearby,
  required Future<List<AreaContentBlock>> Function(String locationId)
      fetchBlocks,
  MasterLocation? Function(String locationId)? locationById,
  List<ContentItem> contentItems = const [],
  DateTime? now,
}) async {
  debugPrint('[GEOFENCE RADIO] GPS: $lat, $lng');
  final rows = await fetchNearby(lat, lng);
  debugPrint('[GEOFENCE RADIO] Nearby geofences: ${rows.length}');

  final insideRows = <String, NearbyGeofence>{
    for (final r in rows) if (r.inside) r.locationId: r,
  };
  final insideIds = insideRows.keys.toSet();
  final candidates = geofenceTriggerCandidates(
    insideIds: insideIds,
    recentIds: state.insidePrev,
    userLat: lat,
    userLng: lng,
    cooldownForLocation: (id) => locationById?.call(id)?.cooldownSeconds,
    playOnceForLocation: (id) => locationById?.call(id)?.playOnce ?? false,
  );
  final fired = engine.evaluate(lat, lng, candidates, now: now);
  state.insidePrev = insideIds;

  final enteredRows = [
    for (final e in fired)
      if (e.kind == LocationTriggerKind.arrival &&
          insideRows[e.locationId] != null)
        insideRows[e.locationId]!,
  ];
  final winner = selectGeofenceToNarrate(enteredRows);
  if (winner == null) return null;
  debugPrint('[GEOFENCE RADIO] Selected location: ${winner.locationName}');
  debugPrint('[GEOFENCE RADIO] location_id: ${winner.locationId}');

  final blocks = await fetchBlocks(winner.locationId);
  final seg = geofenceSegmentFor(
    locationId: winner.locationId,
    locationName: winner.locationName,
    areaBlocks: blocks,
    masterLocation: locationById?.call(winner.locationId),
    contentItems: contentItems,
  );
  if (seg == null) {
    debugPrint(
        '[GEOFENCE RADIO] No content for location: ${winner.locationName}');
    return null;
  }
  debugPrint('[GEOFENCE RADIO] Content: ${seg.title}');
  return seg;
}

/// Level 4 — Geofence radio. On each GPS update, asks the Supabase
/// `get_nearby_geofences()` function what the traveler is inside, feeds that
/// membership through the SAME [LocationTriggerEngine] (enter/exit + play-once
/// + cooldown) used by the POI directors, resolves the winning location's
/// existing content, and interrupts the radio through the existing engine —
/// never touching the audio core, the queue, or wildlife's area-based path.
void _attachGeofenceTriggers(Ref ref) {
  final engine = LocationTriggerEngine();
  final state = GeofenceTickState();
  var inflight = false;

  MasterLocation? locById(String id) {
    for (final l in ref.read(masterLocationsProvider).value ?? const []) {
      if (l.id == id) return l;
    }
    return null;
  }

  Future<void> handle(LocationContext ctx) async {
    if (ctx.latitude == 0 && ctx.longitude == 0) return; // no GPS fix yet
    if (inflight) return; // keep one RPC in flight at a time
    inflight = true;
    try {
      final seg = await geofenceRadioTick(
        lat: ctx.latitude,
        lng: ctx.longitude,
        engine: engine,
        state: state,
        fetchNearby: (a, b) => ref.read(geofenceRepositoryProvider).nearby(a, b),
        fetchBlocks: (id) =>
            ref.read(areaContentRepositoryProvider).forLocation(id),
        locationById: locById,
        contentItems: ref.read(locationContentItemsProvider),
      );
      if (seg == null) return;
      debugPrint('[GEOFENCE RADIO] Triggering radio interruption');
      ref
          .read(radioEngineControllerProvider.notifier)
          .requestInterruption(seg);
      debugPrint('[GEOFENCE RADIO] Playback request completed');
    } catch (_) {
      // Never let a geofence/network hiccup break the radio session.
    } finally {
      inflight = false;
    }
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
  // The active event/park/spring/town/county tier is the reliable, distance-
  // ranked signal for "where the visitor actually is" — GpsBanterDirector
  // matches a destination-scoped clip's gps_region against this park value
  // (substring match), so feeding it the old park-boundary id / station name
  // meant destination-scoped banter (e.g. OCK_RIVER's "Ocklawaha River"
  // region) could never match regardless of location. Same precedence used
  // for upcomingAttraction below.
  final playerCtx = ref.read(playerLocationContextProvider);
  final park =
      playerCtx?.title ?? t.currentParkId ?? stationName?.replaceAll(' Radio', '');
  final upcoming =
      playerCtx?.title ??
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
    station: stationName ?? 'Sunshine Travel Radio',
    // DJ Sunny — the permanent on-air host (see DjBanterScheduler.djName) —
    // so GPS Banter Studio clips' {dj} placeholder resolves to her name too,
    // the same identity used by the template-banter path.
    dj: engine.djBanter.djName,
    // Time-of-day + season + live-weather aware banter.
    moment: BanterMoment.now(
      weatherCondition: w?.condition,
      tempF: w?.temperatureF ?? w?.highF,
    ),
  );
}

/// The programming scheduler (singleton). Retained only for the admin
/// "Test announcement" (fireNow) button — the periodic driver was removed in
/// Scheduler Reconciliation Step 2 in favor of the unified automation tick, so
/// safety/wildlife/story now flow through the single AutomationEngine path.
final radioSchedulerProvider = Provider<RadioScheduler>((ref) {
  return RadioScheduler(
    client: SupabaseService.isConfigured ? SupabaseService.client : null,
    inject: (seg) => ref
        .read(radioEngineControllerProvider.notifier)
        .requestInterruption(seg),
  );
});
