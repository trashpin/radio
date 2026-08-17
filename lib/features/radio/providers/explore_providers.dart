import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/admin/counties/county_config.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config_repository.dart';
import 'package:explorer_os_mobile/features/destinations/data/master_destination_repository.dart';
import 'package:explorer_os_mobile/features/destinations/models/master_destination.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
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
};

/// WHERE YOU ARE — the same EVENT>PARK>SPRING>TOWN>COUNTY tier the player
/// already shows (`playerLocationContextProvider`), reused as-is.
ExploreCandidate? _whereYouAreCandidate(Ref ref) {
  final ctx = ref.watch(playerLocationContextProvider);
  final text = (ctx?.teaser ?? '').trim();
  if (ctx == null || text.isEmpty) return null;
  return ExploreCandidate(
    id: 'whereyouare:${ctx.tellMeMoreContext.locationId ?? ctx.tellMeMoreContext.subject ?? ctx.title}',
    category: ExploreCategory.whereYouAre,
    title: ctx.title,
    spokenText: text,
    tellMeMoreContext: ctx.tellMeMoreContext,
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
    default:
      return null;
  }
}

/// WHERE YOU'RE HEADED — reuses [nearbyLocationsProvider] (the same ranked
/// list Radio/DISCOVER already read) and the existing heading/bearing math
/// ([GeoMath]) to find the next park/spring/town ahead of the current
/// heading, excluding whatever WHERE YOU ARE is already covering. Falls back
/// to the next-nearest such place when heading isn't reliable — never
/// guesses (spec section 4.1).
ExploreCandidate? _whereHeadedCandidate(Ref ref, ExploreCandidate? whereYouAre) {
  final nearby = ref.watch(nearbyLocationsProvider);
  if (nearby.isEmpty) return null;
  final travel = ref.watch(gpsControllerProvider);
  final headingDeg = travel.heading?.degrees ?? travel.bearingDegrees;
  final userLoc = travel.location;
  final currentId = whereYouAre?.tellMeMoreContext?.locationId;

  NearbyLocation? eligible(bool Function(NearbyLocation) test) {
    for (final n in nearby) {
      if (!_kEligibleHeadedTypes.contains(n.location.type)) continue;
      if (n.location.id == currentId) continue;
      if (!n.location.hasCoordinates) continue;
      if (test(n)) return n;
    }
    return null;
  }

  NearbyLocation? picked;
  if (headingDeg != null && userLoc != null) {
    picked = eligible((n) {
      final bearingTo = GeoMath.bearingDegrees(
        userLoc.latitude,
        userLoc.longitude,
        n.location.latitude!,
        n.location.longitude!,
      );
      return GeoMath.angularDifference(bearingTo, headingDeg) <= 70;
    });
  }
  picked ??= eligible((_) => true);
  if (picked == null) return null;

  final kind = _kindFor(picked.location.type);
  if (kind == null) return null;
  final ctx = playerContextForLocation(kind, picked);
  final teaser = (ctx.teaser ?? '').trim();
  if (teaser.isEmpty) return null;
  return ExploreCandidate(
    id: 'whereheaded:${picked.location.id}',
    category: ExploreCategory.whereHeaded,
    title: ctx.title,
    spokenText: "Coming up ahead: ${ctx.title}. $teaser",
    tellMeMoreContext: ctx.tellMeMoreContext,
  );
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

  final out = <ExploreCandidate>[];
  final history = (marion.history ?? '').trim();
  if (history.isNotEmpty) {
    out.add(ExploreCandidate(
      id: 'county:marion:history',
      category: ExploreCategory.county,
      title: 'Marion County History',
      spokenText: history,
      tellMeMoreContext: ctxFor(history),
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
    ));
  }
  return out;
}

/// WILDLIFE/NATURE/HISTORY from the geocoded `location_content` index — the
/// same content the Background Discovery Engine already teaches from between
/// songs, filtered to Marion County (or area-general items with no county
/// set). Reused, not duplicated.
Map<ExploreCategory, List<ExploreCandidate>> _fromLocationContent(
    List<ContentItem> items) {
  final out = <ExploreCategory, List<ExploreCandidate>>{
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
    ));
  }
  return out;
}

/// Birds count as WILDLIFE per this feature's spec (section 4.4), not
/// nature — distinct from the older `DiscoveryCategory` taxonomy elsewhere in
/// the radio engine, which splits them out.
ExploreCategory? _bucketForContentCategory(ContentCategory c) {
  switch (c) {
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
    case ContentCategory.countyHistory:
    case ContentCategory.cityHistory:
    case ContentCategory.historicLandmark:
    case ContentCategory.historicHighway:
    case ContentCategory.communityStory:
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
    ));
  }
  return out;
}

bool _isWildlifeSpeciesCategory(String category) {
  final c = category.toLowerCase();
  return c.contains('bird') ||
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
  final whereHeaded = _whereHeadedCandidate(ref, whereYouAre);

  final pool = <ExploreCategory, List<ExploreCandidate>>{
    for (final c in ExploreCategory.values) c: [],
  };
  if (whereYouAre != null) pool[ExploreCategory.whereYouAre]!.add(whereYouAre);
  if (whereHeaded != null) pool[ExploreCategory.whereHeaded]!.add(whereHeaded);
  pool[ExploreCategory.county]!.addAll(_countyCandidates(ref));

  _mergeInto(pool, _fromLocationContent(ref.watch(locationContentItemsProvider)));

  final destinations =
      ref.watch(masterDestinationsProvider).value ?? const <MasterDestination>[];
  final marionDestinations = <String, MasterDestination>{
    for (final d in destinations)
      if ((d.county ?? '').trim().toLowerCase() == 'marion') d.id: d,
  };
  final narrations = ref.watch(explorePublishedNarrationsProvider).value ??
      const <DestinationNarration>[];
  _mergeInto(pool, _fromDestinationNarrations(narrations, marionDestinations));

  final species = ref.watch(allSpeciesProvider).value ?? const <Species>[];
  _mergeInto(pool, _fromSpecies(species));

  return pool;
});
