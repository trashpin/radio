import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// True when [url] is non-empty but not a usable http(s) link.
bool isBrokenAudioLink(String? url) {
  final u = (url ?? '').trim();
  if (u.isEmpty) return false; // empty = "missing", not "broken"
  final uri = Uri.tryParse(u);
  if (uri == null || !uri.hasScheme) return true;
  if (uri.scheme != 'http' && uri.scheme != 'https') return true;
  return !uri.hasAuthority;
}

/// Aggregate health of the master location database — what's ready vs. what
/// needs attention.
class LocationHealth {
  const LocationHealth({
    required this.total,
    required this.ready,
    required this.pending,
    required this.disabled,
    required this.missingAudio,
    required this.missingImages,
    required this.missingCoordinates,
    required this.missingDescription,
    required this.missingNarration,
    required this.brokenAudio,
    required this.hidden,
    this.lastGenerated,
  });

  final int total;
  final int ready;
  final int pending;
  final int disabled;
  final int missingAudio;
  final int missingImages;
  final int missingCoordinates;
  final int missingDescription;
  final int missingNarration;
  final int brokenAudio;
  final int hidden;
  final DateTime? lastGenerated;

  /// Fraction of locations that are Ready (0..1).
  double get readyProgress => total == 0 ? 0 : ready / total;

  static const empty = LocationHealth(
    total: 0,
    ready: 0,
    pending: 0,
    disabled: 0,
    missingAudio: 0,
    missingImages: 0,
    missingCoordinates: 0,
    missingDescription: 0,
    missingNarration: 0,
    brokenAudio: 0,
    hidden: 0,
  );
}

/// A "missing content" facet the admin can filter/count by.
enum MissingContent { images, narration, gps, description }

extension MissingContentLabel on MissingContent {
  String get label => switch (this) {
    MissingContent.images => 'Missing images',
    MissingContent.narration => 'Missing narration',
    MissingContent.gps => 'Missing GPS',
    MissingContent.description => 'Missing description',
  };
}

/// True when [l] is missing the given content facet. Shared by the dashboard
/// counts and the admin search filter so they never disagree. Disabled
/// locations are ignored for content facets (they're intentionally off).
bool locationIsMissing(MasterLocation l, MissingContent m) {
  switch (m) {
    case MissingContent.gps:
      return !l.hasCoordinates;
    case MissingContent.images:
      return l.status != LocationStatus.disabled && l.images.isEmpty;
    case MissingContent.narration:
      return l.status != LocationStatus.disabled &&
          !l.hasNarration &&
          (l.narrationScript ?? '').trim().isEmpty;
    case MissingContent.description:
      return l.status != LocationStatus.disabled && l.bestDescription == null;
  }
}

/// Per-location content completeness — the admin checklist (Hero / Gallery /
/// Narration / GPS / Map) and a completion percentage.
class LocationCompletion {
  const LocationCompletion({
    required this.hero,
    required this.gallery,
    required this.narration,
    required this.gps,
    required this.map,
  });

  final bool hero; // has at least one image
  final bool gallery; // has gallery images beyond the hero
  final bool narration; // has narration/audio
  final bool gps; // has coordinates
  final bool map; // visible on the map (active + not hidden)

  int get present =>
      [hero, gallery, narration, gps, map].where((b) => b).length;
  int get percent => (present / 5 * 100).round();
  bool get complete => present == 5;
}

LocationCompletion completionFor(MasterLocation l) => LocationCompletion(
  hero: l.images.isNotEmpty,
  gallery: l.images.length >= 2,
  narration: l.hasNarration,
  gps: l.hasCoordinates,
  map: l.active && !l.hidden,
);

/// Image-library health across all locations.
class ImageHealth {
  const ImageHealth({
    required this.totalImages,
    required this.withHero,
    required this.missingHero,
    required this.missingGallery,
    required this.brokenImageLinks,
    required this.duplicateImages,
    required this.locationsComplete,
    required this.locations,
  });

  final int totalImages;
  final int withHero; // visible locations that have a hero
  final int missingHero; // visible locations with no image ("unassigned")
  final int missingGallery;
  final int brokenImageLinks;
  final int duplicateImages;
  final int locationsComplete; // 100% checklist
  final int locations;

  static const empty = ImageHealth(
    totalImages: 0,
    withHero: 0,
    missingHero: 0,
    missingGallery: 0,
    brokenImageLinks: 0,
    duplicateImages: 0,
    locationsComplete: 0,
    locations: 0,
  );
}

ImageHealth computeImageHealth(List<MasterLocation> all) {
  var total = 0, withHero = 0, missingHero = 0, missingGallery = 0;
  var broken = 0, complete = 0;
  final seen = <String>{};
  final dupes = <String>{};
  for (final l in all) {
    total += l.images.length;
    for (final u in l.images) {
      final key = u.trim();
      if (key.isEmpty) continue;
      if (!seen.add(key)) dupes.add(key);
      if (isBrokenAudioLink(u)) broken++;
    }
    final visible = l.active && !l.hidden;
    if (visible && l.images.isEmpty) missingHero++;
    if (visible && l.images.isNotEmpty) withHero++;
    if (visible && l.images.length < 2) missingGallery++;
    if (completionFor(l).complete) complete++;
  }
  return ImageHealth(
    totalImages: total,
    withHero: withHero,
    missingHero: missingHero,
    missingGallery: missingGallery,
    brokenImageLinks: broken,
    duplicateImages: dupes.length,
    locationsComplete: complete,
    locations: all.length,
  );
}

LocationHealth computeLocationHealth(List<MasterLocation> all) {
  var ready = 0, pending = 0, disabled = 0;
  var missingAudio = 0,
      missingImages = 0,
      missingCoords = 0,
      broken = 0,
      hidden = 0;
  var missingDesc = 0, missingNarration = 0;
  DateTime? last;
  for (final l in all) {
    switch (l.status) {
      case LocationStatus.ready:
        ready++;
        if (l.updatedAt != null &&
            (last == null || l.updatedAt!.isAfter(last))) {
          last = l.updatedAt;
        }
      case LocationStatus.pending:
        pending++;
      case LocationStatus.disabled:
        disabled++;
    }
    if (l.status != LocationStatus.disabled && !l.hasAudio) missingAudio++;
    if (locationIsMissing(l, MissingContent.images)) missingImages++;
    if (locationIsMissing(l, MissingContent.gps)) missingCoords++;
    if (locationIsMissing(l, MissingContent.description)) missingDesc++;
    if (locationIsMissing(l, MissingContent.narration)) missingNarration++;
    if (!l.active || l.hidden) hidden++;
    for (final u in l.audioFiles) {
      if (isBrokenAudioLink(u)) broken++;
    }
  }
  return LocationHealth(
    total: all.length,
    ready: ready,
    pending: pending,
    disabled: disabled,
    missingAudio: missingAudio,
    missingImages: missingImages,
    missingCoordinates: missingCoords,
    missingDescription: missingDesc,
    missingNarration: missingNarration,
    brokenAudio: broken,
    hidden: hidden,
    lastGenerated: last,
  );
}

/// Locations sorted most-recently-updated first (for a "Recently updated" list).
List<MasterLocation> recentlyUpdated(
  List<MasterLocation> all, {
  int limit = 10,
}) {
  final withDates = all.where((l) => l.updatedAt != null).toList()
    ..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
  return withDates.take(limit).toList();
}

/// Locations sorted most-recently-created first (for a "Recently added" list).
List<MasterLocation> recentlyAdded(List<MasterLocation> all, {int limit = 10}) {
  final withDates = all.where((l) => l.createdAt != null).toList()
    ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
  return withDates.take(limit).toList();
}

/// Per-county content-readiness rollup for the County Completion Dashboard.
/// Every count is scoped to locations whose `county` matches [county]
/// (case-insensitively).
class CountyCompletion {
  const CountyCompletion({
    required this.county,
    required this.totalLocations,
    required this.totalCities,
    required this.totalCommunities,
    required this.totalAttractions,
    required this.museumsComplete,
    required this.museumsTotal,
    required this.parksComplete,
    required this.parksTotal,
    required this.trailsComplete,
    required this.trailsTotal,
    required this.hiddenGemsComplete,
    required this.hiddenGemsTotal,
    required this.narrationsComplete,
    required this.imagesComplete,
    required this.gpsVerified,
    required this.overallCompletionPercent,
  });

  final String county;
  final int totalLocations;
  final int totalCities;
  final int totalCommunities;
  final int totalAttractions;

  final int museumsComplete;
  final int museumsTotal;
  final int parksComplete;
  final int parksTotal;
  final int trailsComplete;
  final int trailsTotal;
  final int hiddenGemsComplete;
  final int hiddenGemsTotal;

  final int narrationsComplete;
  final int imagesComplete;
  final int gpsVerified;

  /// Average of every location's [LocationCompletion.percent] (the existing
  /// hero/gallery/narration/gps/map checklist) across the whole county —
  /// 0..100, rounded.
  final int overallCompletionPercent;
}

bool _isParkType(LocationType t) =>
    t == LocationType.statePark ||
    t == LocationType.nationalPark ||
    t == LocationType.countyPark;

bool _isTrailType(LocationType t) =>
    t == LocationType.trail || t == LocationType.trailhead;

/// Rolls up completion for every location in [county] (case-insensitive
/// match against [MasterLocation.county]). Pure — no I/O, easy to test.
CountyCompletion computeCountyCompletion(
  List<MasterLocation> all, {
  required String county,
}) {
  final key = county.trim().toLowerCase();
  final scoped =
      all.where((l) => (l.county ?? '').trim().toLowerCase() == key).toList();

  int countType(LocationType t) => scoped.where((l) => l.type == t).length;
  int countComplete(bool Function(LocationType) match) => scoped
      .where((l) => match(l.type) && completionFor(l).complete)
      .length;
  int countTotal(bool Function(LocationType) match) =>
      scoped.where((l) => match(l.type)).length;

  final overall = scoped.isEmpty
      ? 0
      : (scoped.map((l) => completionFor(l).percent).reduce((a, b) => a + b) /
              scoped.length)
          .round();

  return CountyCompletion(
    county: county,
    totalLocations: scoped.length,
    totalCities: countType(LocationType.city),
    totalCommunities: countType(LocationType.community),
    totalAttractions: countType(LocationType.attraction),
    museumsComplete: countComplete((t) => t == LocationType.museum),
    museumsTotal: countTotal((t) => t == LocationType.museum),
    parksComplete: countComplete(_isParkType),
    parksTotal: countTotal(_isParkType),
    trailsComplete: countComplete(_isTrailType),
    trailsTotal: countTotal(_isTrailType),
    hiddenGemsComplete: countComplete((t) => t == LocationType.hiddenGem),
    hiddenGemsTotal: countTotal((t) => t == LocationType.hiddenGem),
    narrationsComplete: scoped.where((l) => l.hasNarration).length,
    imagesComplete: scoped.where((l) => l.images.isNotEmpty).length,
    gpsVerified: scoped.where((l) => l.hasCoordinates).length,
    overallCompletionPercent: overall,
  );
}

/// One [CountyCompletion] per distinct county found in [all] (case-
/// insensitive grouping; locations with no county set are excluded), sorted
/// alphabetically.
List<CountyCompletion> computeCountyCompletions(List<MasterLocation> all) {
  final byKey = <String, String>{}; // lowercase key -> first-seen display name
  for (final l in all) {
    final name = (l.county ?? '').trim();
    if (name.isEmpty) continue;
    byKey.putIfAbsent(name.toLowerCase(), () => name);
  }
  final names = byKey.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [
    for (final name in names) computeCountyCompletion(all, county: name),
  ];
}
