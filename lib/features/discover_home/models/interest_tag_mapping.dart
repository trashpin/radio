import 'package:explorer_os_mobile/features/discover_home/models/discover_interest.dart';
import 'package:explorer_os_mobile/features/events/models/local_event.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Maps existing content taxonomy (LocationType, Nearby Gem category, event
/// data) onto the fixed interest tokens in [discoverInterests] — no new
/// content-classification system, just a grouping of what each record
/// already declares itself to be.
const Map<LocationType, Set<String>> _locationTypeInterests = {
  LocationType.lake: {'springs_water', 'boating', 'fishing', 'outdoors'},
  LocationType.river: {'springs_water', 'boating', 'fishing', 'outdoors'},
  LocationType.spring: {'springs_water', 'outdoors', 'adventure'},
  LocationType.boatRamp: {'boating', 'springs_water', 'fishing'},
  LocationType.forest: {'outdoors', 'wildlife', 'hiking_trails', 'adventure'},
  LocationType.nationalForest: {'outdoors', 'wildlife', 'hiking_trails', 'adventure'},
  LocationType.stateForest: {'outdoors', 'wildlife', 'hiking_trails', 'adventure'},
  LocationType.wildlifeManagementArea: {'outdoors', 'wildlife', 'adventure'},
  LocationType.wildlifeViewing: {'wildlife', 'outdoors', 'birds'},
  LocationType.statePark: {'outdoors', 'family', 'hiking_trails'},
  LocationType.nationalPark: {'outdoors', 'family', 'hiking_trails'},
  LocationType.countyPark: {'outdoors', 'family', 'hiking_trails'},
  LocationType.cityPark: {'outdoors', 'family', 'hiking_trails'},
  LocationType.historicSite: {'history'},
  LocationType.historicDistrict: {'history'},
  LocationType.monument: {'history'},
  LocationType.memorial: {'history'},
  LocationType.lighthouse: {'history', 'photography'},
  LocationType.scenicRoad: {'photography', 'outdoors', 'adventure'},
  LocationType.scenicOverlook: {'photography', 'outdoors', 'adventure'},
  LocationType.trail: {'hiking_trails', 'outdoors', 'adventure'},
  LocationType.trailhead: {'hiking_trails', 'outdoors', 'adventure'},
  LocationType.campground: {'outdoors', 'adventure', 'family'},
  LocationType.museum: {'history', 'arts_culture', 'family'},
  LocationType.waterfall: {'outdoors', 'adventure', 'photography'},
  LocationType.cave: {'outdoors', 'adventure', 'photography'},
  LocationType.beach: {'outdoors', 'family', 'photography'},
  LocationType.festivalGrounds: {'festivals', 'live_music', 'local_events'},
  LocationType.eventVenue: {'festivals', 'live_music', 'local_events'},
  LocationType.attraction: {'family', 'local_events'},
  LocationType.hiddenGem: {'local_events'},
  LocationType.pointOfInterest: {'local_events'},
  LocationType.localAttraction: {'family', 'local_events'},
};

Set<String> interestTagsForLocationType(LocationType type) =>
    _locationTypeInterests[type] ?? const {};

/// Gem categories (see [NearbyGem.categoryOptions]) mapped the same way.
/// Food/lodging categories (Restaurant, Coffee, Ice Cream, Bakery, Dessert,
/// Lodging, Other) intentionally have no interest match today — none of the
/// 22 interests cover "food" or "lodging"; those gems still surface in NEAR
/// YOU by distance, just not in interest-driven sections. A future "Food &
/// Drink" interest would close this gap.
Set<String> interestTagsForGemCategory(String? category) {
  switch ((category ?? '').trim().toLowerCase()) {
    case 'shopping':
      return {'shopping', 'markets'};
    case 'museum':
      return {'history', 'arts_culture'};
    case 'outdoors':
      return {'outdoors', 'adventure'};
    case 'attraction':
      return {'local_events'};
    case 'bar':
      return {'nightlife'};
    default:
      return const {};
  }
}

/// Keyword phrases that infer an interest from free-text event name/
/// description — a heuristic fallback ONLY (never invents facts, only
/// categorizes existing text) used until events are explicitly tagged via
/// `events.category`/`interest_tags` (both new, empty-by-default columns).
const Map<String, Set<String>> _eventKeywordInterests = {
  'concert': {'live_music'},
  'live music': {'live_music'},
  'band': {'live_music'},
  'festival': {'festivals'},
  'fest': {'festivals'},
  'market': {'markets'},
  'farmers market': {'markets', 'free_things'},
  'horse': {'horses_equestrian'},
  'equestrian': {'horses_equestrian'},
  'rodeo': {'horses_equestrian'},
  'car show': {'cars_trucks'},
  'cruise-in': {'cars_trucks'},
  'truck': {'cars_trucks'},
  'kids': {'kids', 'family'},
  'children': {'kids', 'family'},
  'family': {'family'},
  'free': {'free_things'},
  'art': {'arts_culture'},
  'craft': {'arts_culture'},
  'history': {'history'},
  'historic': {'history'},
  'fishing': {'fishing'},
  'boat': {'boating'},
  'photography': {'photography'},
  'hike': {'hiking_trails'},
  'trail': {'hiking_trails'},
};

/// Every interest tag for an event: the explicit `interest_tags`/`category`
/// columns (once admin-tagged) union the keyword heuristic over its name and
/// description — never a substitute for real tagging, just a reasonable v1
/// default so recommendations aren't empty before any admin curation exists.
Set<String> interestTagsForEvent(LocalEvent event) {
  final tags = <String>{...event.interestTags};
  if ((event.category ?? '').trim().isNotEmpty) {
    final token = event.category!.trim().toLowerCase().replaceAll(' ', '_');
    if (discoverInterestTokenSet.contains(token)) tags.add(token);
  }
  final haystack =
      '${event.name} ${event.description ?? ''} ${event.shortDescription ?? ''}'
          .toLowerCase();
  for (final entry in _eventKeywordInterests.entries) {
    // Word-boundary match — a plain `contains` would false-positive on
    // substrings inside unrelated words (e.g. "art" inside "quarterly").
    final pattern = RegExp(r'\b' + RegExp.escape(entry.key) + r'\b');
    if (pattern.hasMatch(haystack)) tags.addAll(entry.value);
  }
  return tags;
}

Set<String> get discoverInterestTokenSet =>
    discoverInterestsByToken.keys.toSet();
