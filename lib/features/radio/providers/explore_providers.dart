import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/counties/county_config.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config_repository.dart';
import 'package:explorer_os_mobile/features/destinations/data/master_destination_repository.dart';
import 'package:explorer_os_mobile/features/destinations/models/master_destination.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/events/data/event_repository.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/attraction_point.dart';
import 'package:explorer_os_mobile/features/gps/services/upcoming_destination_service.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';
import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/location_engine.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/narration/data/destination_narration_repository.dart';
import 'package:explorer_os_mobile/features/narration/models/destination_narration.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';
import 'package:explorer_os_mobile/features/radio/services/explore_rotation_scheduler.dart';
import 'package:explorer_os_mobile/features/radio/services/player_location_context.dart';

/// Marion County Explore — MODE STATE
///
/// Whether the traveler has switched the player to MARION COUNTY EXPLORE.
class ExploreModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
  void toggle() => state = !state;
}

final exploreModeProvider =
    NotifierProvider<ExploreModeNotifier, bool>(ExploreModeNotifier.new);

/// True only while the traveler is in Marion County — reuses
/// [locationContextProvider].county, the SAME county signal the existing
/// County Welcome / DJ county-facts directors already depend on (derived from
/// the nearest geocoded `location_content`, not a separate county-boundary
/// dataset — [gpsControllerProvider]'s own `currentCounty` is a boundary-
/// polygon detector that isn't reliably seeded everywhere yet, which is why
/// this reuses the proven signal instead of introducing a second one).
/// Explore is Marion-only for this first phase (spec section 1).
final marionCountyActiveProvider = Provider<bool>((ref) {
  final county = ref.watch(locationContextProvider).county;
  return (county ?? '').trim().toLowerCase() == 'marion';
});

/// The actual signal the engine/UI act on: the traveler wants Explore AND is
/// currently inside Marion County. Automatically suspends outside Marion
/// (without losing the toggle preference or the rotation position — see
/// [ExploreRotationScheduler.setExploreMode]) and resumes on return.
final exploreActiveProvider = Provider<bool>((ref) {
  return ref.watch(exploreModeProvider) && ref.watch(marionCountyActiveProvider);
});

// ── Content sourcing — every category reuses an existing table/provider ─────

const _kEligibleHeadedTypes = {
  LocationType.statePark,
  LocationType.nationalPark,
  LocationType.countyPark,
  LocationType.spring,
  LocationType.city,
  LocationType.community,
  LocationType.historicSite,
  LocationType.museum,
  LocationType.attraction,
};

/// WHERE YOU ARE — the same EVENT>PARK>SPRING>TOWN>COUNTY tier the player
/// already shows (`playerLocationContextProvider`), reused as-is.
ExploreCandidate? _whereYouAreCandidate(Ref ref) {
  final ctx = ref.watch(playerLocationContextProvider);
  final text = (ctx?.teaser ?? '').trim();
  if (ctx == null || text.isEmpty) return null;
  final loc = ctx.tellMeMoreContext.location;
  return ExploreCandidate(
    id: 'whereyouare:${ctx.tellMeMoreContext.locationId ?? ctx.tellMeMoreContext.subject ?? ctx.title}',
    category: ExploreCategory.whereYouAre,
    title: ctx.title,
    spokenText: text,
    tellMeMoreContext: ctx.tellMeMoreContext,
    imageUrl: ctx.imageUrl,
    latitude: loc?.latitude,
    longitude: loc?.longitude,
  );
}

PlayerLocationKind? _kindFor(LocationType t) {
  switch (t) {
    case LocationType.statePark:
    case LocationType.nationalPark:
    case LocationType.countyPark:
      return PlayerLocationKind.park;
    case LocationType.spring:
      return PlayerLocationKind.spring;
    case LocationType.city:
    case LocationType.community:
      return PlayerLocationKind.town;
    case LocationType.historicSite:
    case LocationType.museum:
    case LocationType.attraction:
      return PlayerLocationKind.attraction;
    default:
      return null;
  }
}

/// Type-based "what's ahead" priority (spec: Park > State Park > Attraction >
/// Historical Site > Event > Town > County — lower wins) used to rank several
/// SIMULTANEOUSLY-qualifying ahead candidates against each other, distinct
/// from the distance/cone filtering that decides whether a candidate
/// qualifies at all. State Park and Spring are tied at the top (both
/// flagship destinations in this app); city/county Park sits just below.
int _aheadTypePriority(LocationType t) {
  switch (t) {
    case LocationType.statePark:
    case LocationType.nationalPark:
    case LocationType.spring:
      return 0;
    case LocationType.countyPark:
    case LocationType.cityPark:
      return 1;
    case LocationType.attraction:
    case LocationType.museum:
    case LocationType.pointOfInterest:
      return 2;
    case LocationType.historicSite:
    case LocationType.historicDistrict:
      return 3;
    case LocationType.city:
    case LocationType.community:
    case LocationType.town:
    case LocationType.village:
      return 5;
    default:
      return 6;
  }
}

const _kEventAheadPriority = 4; // between Historical Site and Town

/// Full reveal (distance + story) once genuinely close; a vague teaser
/// beyond that but still in-cone/in-range. Nests inside the urgent-interrupt
/// threshold (≤1mi/3min, in `radio_session_provider.dart`'s `checkUrgent`) so
/// anything urgent is always already a full-reveal candidate by the time it
/// crosses that closer threshold.
const double _kFullRevealMaxMeters = 5 * 1609.344; // ~5 miles
const Duration _kFullRevealMaxEta = Duration(minutes: 8);

/// WHAT'S AHEAD — merges eligible master locations (parks/springs/towns/
/// historic sites/museums) and nearby events into ONE directional search via
/// the existing [UpcomingDestinationService] (the same cone + radius + ETA
/// detector the GPS engine already uses elsewhere for "what's coming up on
/// my route"), excluding whatever WHERE YOU ARE already covers. Returns up
/// to 5 nearest-in-cone candidates (not just the first) so the scheduler's
/// per-category no-repeat can move on to the next-nearest still-ahead place
/// once the nearest one has aired, instead of the tier going empty.
///
/// Deliberately NO fallback to "nearest regardless of heading" — with no
/// GPS fix or no reliable heading there is nothing genuinely ahead yet, and
/// the rotation falls through to WILDLIFE/NATURE instead. A location behind
/// the user must never be treated as What's Ahead.
List<ExploreCandidate> _aheadCandidates(Ref ref, ExploreCandidate? whereYouAre) {
  final travel = ref.watch(gpsControllerProvider);
  final userLoc = travel.location;
  final headingDeg = travel.heading?.degrees ?? travel.bearingDegrees;
  if (userLoc == null || headingDeg == null) return const [];

  final allLocations =
      ref.watch(masterLocationsProvider).value ?? const <MasterLocation>[];
  final engine = ref.watch(locationEngineProvider);
  final currentId = whereYouAre?.tellMeMoreContext?.locationId;

  // Sources directly from the master locations dataset with Explore's OWN
  // type filter — deliberately bypasses nearbyLocationsProvider's
  // onlyActiveTypes() gate (a separate, global allow-list this feature must
  // not widen) so historic sites/museums can be considered here.
  final nearby = engine.nearby(
    userLoc.latitude,
    userLoc.longitude,
    allLocations,
    maxMiles: 20,
    types: _kEligibleHeadedTypes,
  );

  final points = <AttractionPoint>[];
  final byId = <String, Object>{};
  for (final n in nearby) {
    if (n.location.id == currentId) continue;
    if (!n.location.hasCoordinates) continue;
    final id = 'loc:${n.location.id}';
    points.add(AttractionPoint(
      id: id,
      name: n.location.name,
      latitude: n.location.latitude!,
      longitude: n.location.longitude!,
    ));
    byId[id] = n;
  }
  for (final e in ref.watch(nearbyEventsProvider)) {
    final lat = e.event.latitude;
    final lng = e.event.longitude;
    if (lat == null || lng == null) continue;
    final id = 'evt:${e.event.id}';
    points.add(AttractionPoint(
      id: id,
      name: e.event.name,
      latitude: lat,
      longitude: lng,
    ));
    byId[id] = e;
  }
  if (points.isEmpty) return const [];

  final results = const UpcomingDestinationService().search(
    points,
    userLoc,
    headingDeg,
    coneDegrees: 60,
    radiusMeters: 20000,
    speedMps: userLoc.speedMps,
    limit: 10, // headroom for type-priority ranking, not just nearest-5
  );

  final out = <ExploreCandidate>[];
  for (final r in results) {
    final source = byId[r.id];
    final PlayerLocationContext ctx;
    final ExploreCategory category;
    final int aheadPriority;
    if (source is NearbyLocation) {
      final kind = _kindFor(source.location.type);
      if (kind == null) continue;
      ctx = playerContextForLocation(kind, source);
      category = ExploreCategory.whereHeaded;
      aheadPriority = _aheadTypePriority(source.location.type);
    } else if (source is NearbyEvent) {
      ctx = playerContextForEvent(source);
      category = ExploreCategory.events;
      aheadPriority = _kEventAheadPriority;
    } else {
      continue;
    }
    final teaser = (ctx.teaser ?? '').trim();
    if (teaser.isEmpty) continue; // never invent content — same guard as before

    final closeEnoughToReveal = r.distanceMeters <= _kFullRevealMaxMeters ||
        (r.eta != null && r.eta! <= _kFullRevealMaxEta);
    if (closeEnoughToReveal) {
      final miles = r.distanceMeters / 1609.344;
      final leadPhrase =
          "You're about ${miles.toStringAsFixed(miles < 10 ? 1 : 0)} "
          "miles from ${ctx.title}.";
      out.add(ExploreCandidate(
        id: 'ahead:${r.id}',
        category: category,
        title: ctx.title,
        spokenText: '$leadPhrase $teaser',
        tellMeMoreContext: ctx.tellMeMoreContext,
        imageUrl: ctx.imageUrl,
        latitude: r.latitude,
        longitude: r.longitude,
        distanceMeters: r.distanceMeters,
        eta: r.eta,
        aheadPriority: aheadPriority,
      ));
    } else {
      // Still too far for the full story — a vague pre-arrival teaser
      // instead. Carries the SAME image/nav/location as the real place (so
      // NAVIGATE and the hero image stay meaningful) but the scheduler
      // always overrides spokenText with varied, non-specific phrasing —
      // this placeholder only exists to satisfy ExploreCandidate.isPlayable.
      out.add(ExploreCandidate(
        id: 'tease:${r.id}',
        category: ExploreCategory.teaser,
        title: ctx.title,
        spokenText: 'Something interesting is coming up ahead.',
        tellMeMoreContext: ctx.tellMeMoreContext,
        imageUrl: ctx.imageUrl,
        latitude: r.latitude,
        longitude: r.longitude,
        distanceMeters: r.distanceMeters,
        eta: r.eta,
        aheadPriority: aheadPriority,
      ));
    }
  }
  return out;
}

/// MARION COUNTY — CountyConfig's history/overview/facts (Admin → County
/// Manager), split into a few short items so the county tier itself rotates
/// through several tidbits over a longer drive instead of repeating one.
List<ExploreCandidate> _countyCandidates(Ref ref) {
  final configs = ref.watch(countyConfigsProvider).value ?? const <CountyConfig>[];
  CountyConfig? marion;
  for (final c in configs) {
    if (c.key == 'marion') {
      marion = c;
      break;
    }
  }
  if (marion == null) return const [];

  TellMeMoreContext ctxFor(String text) => TellMeMoreContext(
        subject: 'Marion',
        contextKind: 'county',
        banterText: text,
      );

  final image = marion.heroImageUrl;
  final out = <ExploreCandidate>[];
  final history = (marion.history ?? '').trim();
  if (history.isNotEmpty) {
    out.add(ExploreCandidate(
      id: 'county:marion:history',
      category: ExploreCategory.county,
      title: 'Marion County History',
      spokenText: history,
      tellMeMoreContext: ctxFor(history),
      imageUrl: image,
    ));
  }
  final overview = (marion.overview ?? '').trim();
  if (overview.isNotEmpty) {
    out.add(ExploreCandidate(
      id: 'county:marion:overview',
      category: ExploreCategory.county,
      title: 'Marion County',
      spokenText: overview,
      tellMeMoreContext: ctxFor(overview),
      imageUrl: image,
    ));
  }
  for (var i = 0; i < marion.facts.length; i++) {
    final fact = marion.facts[i].trim();
    if (fact.isEmpty) continue;
    out.add(ExploreCandidate(
      id: 'county:marion:fact:$i',
      category: ExploreCategory.county,
      title: 'Marion County',
      spokenText: fact,
      tellMeMoreContext: ctxFor(fact),
      imageUrl: image,
    ));
  }
  return out;
}

/// WHERE YOU ARE/COUNTY/WILDLIFE/NATURE/HISTORY from the geocoded
/// `location_content` index — the same content the Background Discovery
/// Engine already teaches from between songs, filtered to Marion County (or
/// area-general items with no county set). Reused, not duplicated.
///
/// City/community rows (Ocklawaha's own welcome/history/fun-facts/community-
/// story items, etc.) supplement WHERE YOU ARE alongside the single
/// [playerLocationContextProvider] candidate, so the tour actually surfaces
/// what's been written about the specific town the traveler is passing
/// through, not just a single synthesized line. `county_*` rows supplement
/// [_countyCandidates] the same way, so MARION COUNTY plays real authored
/// content even on counties whose CountyConfig (Admin → County Manager)
/// hasn't been filled in yet.
/// WHERE YOU ARE should only ever be about a town the traveler is actually
/// near — a town 20 miles away is not "where you are". Larger than the
/// player's own PARK/SPRING cap (5mi) since towns cover more ground.
const double _kWhereYouAreTownMaxMeters = 10 * 1609.344;

Map<ExploreCategory, List<ExploreCandidate>> _fromLocationContent(
  List<ContentItem> items,
  List<MasterLocation> masterLocations, {
  double? userLat,
  double? userLng,
}) {
  final out = <ExploreCategory, List<ExploreCandidate>>{
    ExploreCategory.whereYouAre: [],
    ExploreCategory.county: [],
    ExploreCategory.wildlife: [],
    ExploreCategory.nature: [],
    ExploreCategory.history: [],
  };
  for (final item in items) {
    final county = (item.county ?? '').trim().toLowerCase();
    if (county.isNotEmpty && county != 'marion') continue;
    final bucket = _bucketForContentCategory(item.category);
    if (bucket == null) continue;
    final text = (item.text ?? '').trim();
    if ((item.audioUrl ?? '').trim().isEmpty && text.isEmpty) continue;
    final lat = item.latitude == 0 ? null : item.latitude;
    final lng = item.longitude == 0 ? null : item.longitude;
    // WHERE YOU ARE items (town welcome/history/fun-facts/community-story)
    // are about ONE specific town — only surface them when the traveler is
    // actually near that town, not every Marion town regardless of position
    // (previously every town's content played as if it were "where you
    // are", which is both misleading and crowded out real variety).
    if (bucket == ExploreCategory.whereYouAre &&
        userLat != null &&
        userLng != null &&
        lat != null &&
        lng != null &&
        GeoMath.distanceMeters(userLat, userLng, lat, lng) >
            _kWhereYouAreTownMaxMeters) {
      continue;
    }
    out[bucket]!.add(ExploreCandidate(
      id: 'content:${item.id}',
      category: bucket,
      title: item.title,
      audioUrl: item.audioUrl,
      spokenText: text.isEmpty ? null : text,
      tellMeMoreContext: TellMeMoreContext(
        subject: item.title,
        banterText: text.isEmpty ? null : text,
      ),
      imageUrl: _imageForContentItem(item, masterLocations),
      latitude: lat,
      longitude: lng,
    ));
  }
  return out;
}

/// Best-effort photo for a `location_content` row (the table itself has no
/// image column) — matches its city/title against the master `locations`
/// table's own name and borrows that record's existing photo. No image is
/// invented when nothing matches; the player simply falls back to its normal
/// artwork (spec: "Do not invent missing information").
String? _imageForContentItem(ContentItem item, List<MasterLocation> locations) {
  final key = (item.city ?? item.title).trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final l in locations) {
    if (l.name.trim().toLowerCase() == key && l.images.isNotEmpty) {
      return l.images.first;
    }
  }
  return null;
}

/// Birds count as WILDLIFE per this feature's spec (section 4.4), not
/// nature — distinct from the older `DiscoveryCategory` taxonomy elsewhere in
/// the radio engine, which splits them out. City/community categories map to
/// WHERE YOU ARE (they're written about a specific town) and `county_*`
/// categories map to MARION COUNTY (spec sections 4.1/4.3) rather than the
/// broader HISTORY bucket, which is reserved for county-wide historical
/// topics not tied to one town.
ExploreCategory? _bucketForContentCategory(ContentCategory c) {
  switch (c) {
    case ContentCategory.cityWelcome:
    case ContentCategory.cityIntro:
    case ContentCategory.cityHistory:
    case ContentCategory.cityFunFacts:
    case ContentCategory.communityStory:
      return ExploreCategory.whereYouAre;
    case ContentCategory.countyWelcome:
    case ContentCategory.countyHistory:
    case ContentCategory.countyFunFacts:
    case ContentCategory.countyAgriculture:
    case ContentCategory.countyEconomy:
    case ContentCategory.countyHiddenGems:
      return ExploreCategory.county;
    case ContentCategory.wildlife:
    case ContentCategory.birds:
      return ExploreCategory.wildlife;
    case ContentCategory.plants:
    case ContentCategory.trees:
    case ContentCategory.water:
    case ContentCategory.riverStory:
    case ContentCategory.lakeStory:
    case ContentCategory.forestStory:
    case ContentCategory.countyNature:
    case ContentCategory.trails:
    case ContentCategory.scenicOverlook:
      return ExploreCategory.nature;
    case ContentCategory.history:
    case ContentCategory.historicLandmark:
    case ContentCategory.historicHighway:
      return ExploreCategory.history;
    default:
      return null;
  }
}

const _kExploreScriptTypes = [
  'wildlife',
  'birds',
  'plants',
  'trees',
  'geology',
  'main_history',
  'extended_history',
];

/// Every PUBLISHED narration of the script types Explore uses, fetched once
/// (bounded query, no per-destination fetching) and filtered to Marion
/// destinations client-side against [destinationsProvider] — the same
/// per-destination script content DJ Banter/Tell Me More already use.
final explorePublishedNarrationsProvider =
    FutureProvider<List<DestinationNarration>>((ref) {
  return ref
      .watch(destinationNarrationRepositoryProvider)
      .publishedForScriptTypes(_kExploreScriptTypes);
});

ExploreCategory? _bucketForScriptType(String scriptType) {
  switch (scriptType) {
    case 'wildlife':
    case 'birds':
      return ExploreCategory.wildlife;
    case 'plants':
    case 'trees':
      return ExploreCategory.nature;
    case 'geology':
      return ExploreCategory.geology;
    case 'main_history':
    case 'extended_history':
      return ExploreCategory.history;
    default:
      return null;
  }
}

/// GEOLOGY (and a WILDLIFE/NATURE/HISTORY supplement) sourced from
/// `destination_narrations` — the only existing system with a `geology`
/// script type. If no Marion destination has geology content generated yet,
/// this bucket is simply empty and the rotation skips it (spec section 5),
/// exactly as intended — no fake content is created to fill the slot.
Map<ExploreCategory, List<ExploreCandidate>> _fromDestinationNarrations(
  List<DestinationNarration> narrations,
  Map<String, MasterDestination> marionDestinationsById,
) {
  final out = <ExploreCategory, List<ExploreCandidate>>{
    ExploreCategory.wildlife: [],
    ExploreCategory.nature: [],
    ExploreCategory.geology: [],
    ExploreCategory.history: [],
  };
  for (final n in narrations) {
    final dest = marionDestinationsById[n.destinationId];
    if (dest == null) continue;
    final bucket = _bucketForScriptType(n.scriptType);
    if (bucket == null) continue;
    final script = (n.script ?? '').trim();
    if (!n.hasAudio && script.isEmpty) continue;
    final title = (n.title ?? '').trim().isNotEmpty ? n.title!.trim() : dest.name;
    out[bucket]!.add(ExploreCandidate(
      id: 'narration:${n.id}',
      category: bucket,
      title: title,
      audioUrl: n.audioUrl,
      spokenText: n.hasAudio ? null : script,
      tellMeMoreContext: TellMeMoreContext(
        subject: dest.name,
        destinationId: dest.id,
        banterText: script.isEmpty ? null : script,
      ),
      imageUrl: dest.heroImage,
      latitude: dest.latitude,
      longitude: dest.longitude,
    ));
  }
  return out;
}

bool _isWildlifeSpeciesCategory(String category) {
  final c = category.toLowerCase();
  // 'animals' is the actual, dominant category value in the live species
  // table (126 of 182 published rows) — it was missing from this list
  // entirely, so every mammal/general-animal species was silently invisible
  // to Explore's WILDLIFE rotation (the single biggest cause of Explore
  // feeling repetitive: the largest content pool wasn't being read at all).
  return c.contains('animal') ||
      c.contains('bird') ||
      c.contains('mammal') ||
      c.contains('reptile') ||
      c.contains('amphibian') ||
      c.contains('fish') ||
      c.contains('insect');
}

bool _isNatureSpeciesCategory(String category) {
  final c = category.toLowerCase();
  return c.contains('plant') || c.contains('tree') || c.contains('flora');
}

/// A light WILDLIFE/NATURE supplement from the master `species` catalog
/// (published only) — species aren't geo-scoped, so these are generic species
/// profiles used to round out the rotation when location-anchored content is
/// thin, not claims about what's visible right now (spec section 4.4).
Map<ExploreCategory, List<ExploreCandidate>> _fromSpecies(List<Species> species) {
  final out = <ExploreCategory, List<ExploreCandidate>>{
    ExploreCategory.wildlife: [],
    ExploreCategory.nature: [],
  };
  for (final s in species) {
    if (!s.published) continue;
    final bucket = _isWildlifeSpeciesCategory(s.category)
        ? ExploreCategory.wildlife
        : _isNatureSpeciesCategory(s.category)
            ? ExploreCategory.nature
            : null;
    if (bucket == null) continue;
    final text = [s.description, s.funFacts]
        .where((t) => (t ?? '').trim().isNotEmpty)
        .map((t) => t!.trim())
        .join(' ');
    if (text.isEmpty) continue;
    out[bucket]!.add(ExploreCandidate(
      id: 'species:${s.id}',
      category: bucket,
      title: s.commonName,
      spokenText: text,
      tellMeMoreContext: TellMeMoreContext(subject: s.commonName, banterText: text),
      imageUrl: s.heroImageUrl,
    ));
  }
  return out;
}

void _mergeInto(
  Map<ExploreCategory, List<ExploreCandidate>> target,
  Map<ExploreCategory, List<ExploreCandidate>> source,
) {
  for (final entry in source.entries) {
    (target[entry.key] ??= []).addAll(entry.value);
  }
}

/// The full Explore candidate pool, one list per category, rebuilt as GPS/
/// content change. This is a plain [Provider] (not Future) so the engine
/// wiring can push it into [ExploreRotationScheduler] synchronously; the two
/// async sources ([explorePublishedNarrationsProvider], [destinationsProvider],
/// [allSpeciesProvider]) degrade to "not loaded yet" (empty) rather than
/// blocking, exactly like every other `.value ?? const []` provider in this
/// codebase.
final exploreCandidatesProvider =
    Provider<Map<ExploreCategory, List<ExploreCandidate>>>((ref) {
  final whereYouAre = _whereYouAreCandidate(ref);
  final ahead = _aheadCandidates(ref, whereYouAre);

  final pool = <ExploreCategory, List<ExploreCandidate>>{
    for (final c in ExploreCategory.values) c: [],
  };
  if (whereYouAre != null) pool[ExploreCategory.whereYouAre]!.add(whereYouAre);
  for (final c in ahead) {
    pool[c.category]!.add(c);
  }
  pool[ExploreCategory.county]!.addAll(_countyCandidates(ref));

  final contentItems = ref.watch(locationContentItemsProvider);
  final masterLocations = ref.watch(masterLocationsProvider).value ??
      const <MasterLocation>[];
  final userLoc = ref.watch(gpsControllerProvider).location;
  _mergeInto(
    pool,
    _fromLocationContent(
      contentItems,
      masterLocations,
      userLat: userLoc?.latitude,
      userLng: userLoc?.longitude,
    ),
  );

  // The live `destinations` table has no `county` column (a MasterDestination
  // field that's never actually populated), so "is this destination in
  // Marion?" is derived the same way [marionCountyActiveProvider] derives the
  // traveler's own county — via the existing LocationIntelligenceEngine
  // against the destination's own coordinates — rather than a field that
  // doesn't exist in the schema.
  final destinations =
      ref.watch(masterDestinationsProvider).value ?? const <MasterDestination>[];
  final engine = ref.watch(locationIntelligenceEngineProvider);
  final marionDestinations = <String, MasterDestination>{
    for (final d in destinations)
      if (d.latitude != null &&
          d.longitude != null &&
          (engine
                      .deriveContext(d.latitude!, d.longitude!, contentItems)
                      .county ??
                  '')
                  .trim()
                  .toLowerCase() ==
              'marion')
        d.id: d,
  };
  final narrations = ref.watch(explorePublishedNarrationsProvider).value ??
      const <DestinationNarration>[];
  _mergeInto(pool, _fromDestinationNarrations(narrations, marionDestinations));

  final species = ref.watch(allSpeciesProvider).value ?? const <Species>[];
  _mergeInto(pool, _fromSpecies(species));

  return pool;
});
