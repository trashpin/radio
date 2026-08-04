import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/location_intelligence/models/content_item.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Narration resolved for a master location — audio if we have it, otherwise a
/// composed script for on-device TTS.
class LocationNarration {
  const LocationNarration({
    required this.title,
    required this.text,
    this.audioUrl,
    this.sourceContentId,
  });

  final String title;
  final String text;
  final String? audioUrl;

  /// The `location_content` row this narration came from, when matched.
  final String? sourceContentId;

  bool get hasAudio => audioUrl != null && audioUrl!.trim().isNotEmpty;
}

/// The `location_content` categories that are relevant to a master
/// [LocationType] — used to attach existing narration to a master location.
Set<ContentCategory> relevantCategories(LocationType t) {
  switch (t) {
    case LocationType.county:
      return {
        ContentCategory.countyWelcome,
        ContentCategory.countyHistory,
        ContentCategory.countyFunFacts,
        ContentCategory.countyNature,
        ContentCategory.countyAgriculture,
        ContentCategory.countyEconomy,
        ContentCategory.countyHiddenGems,
      };
    case LocationType.city:
      return {
        ContentCategory.cityWelcome,
        ContentCategory.cityHistory,
        ContentCategory.cityFunFacts,
        ContentCategory.cityIntro,
      };
    case LocationType.community:
      return {ContentCategory.communityStory};
    case LocationType.spring:
      return {ContentCategory.water};
    case LocationType.river:
      return {ContentCategory.riverStory, ContentCategory.water};
    case LocationType.lake:
      return {ContentCategory.lakeStory, ContentCategory.water};
    case LocationType.forest:
      return {ContentCategory.forestStory, ContentCategory.park};
    case LocationType.statePark:
    case LocationType.nationalPark:
    case LocationType.countyPark:
      return {
        ContentCategory.park,
        ContentCategory.parkStory,
        ContentCategory.arrival,
        ContentCategory.wildlife,
        ContentCategory.plants,
      };
    case LocationType.historicSite:
    case LocationType.historicDistrict:
      return {ContentCategory.history, ContentCategory.historicLandmark};
    case LocationType.scenicRoad:
      return {
        ContentCategory.scenicDrive,
        ContentCategory.scenicRoad,
        ContentCategory.historicHighway,
      };
    case LocationType.trail:
    case LocationType.trailhead:
      return {ContentCategory.trails};
    case LocationType.scenicOverlook:
      return {ContentCategory.scenicOverlook};
    case LocationType.museum:
      return {ContentCategory.museum};
    case LocationType.restaurant:
      return {ContentCategory.restaurant};
    case LocationType.hiddenGem:
      return {ContentCategory.hiddenGem};
    case LocationType.wildlifeViewing:
      return {ContentCategory.wildlife, ContentCategory.birds};
    default:
      return {ContentCategory.attraction, ContentCategory.history};
  }
}

/// The persistable narration link for a master location: the matching
/// `location_content` ids (best-first) and their audio files.
class LocationNarrationLinks {
  const LocationNarrationLinks(this.narrationIds, this.audioFiles);
  final List<String> narrationIds;
  final List<String> audioFiles;
  bool get isEmpty => narrationIds.isEmpty && audioFiles.isEmpty;
}

/// Resolves every `location_content` narration that belongs to [loc] within
/// [radiusMeters] (best-first by name/category/audio/proximity), so the link
/// can be persisted into `locations.narration_ids` / `audio_files`.
LocationNarrationLinks resolveNarrationLinks(
  MasterLocation loc,
  List<ContentItem> content, {
  double radiusMeters = 1609.344,
}) {
  if (!loc.hasCoordinates) return const LocationNarrationLinks([], []);
  final relevant = relevantCategories(loc.type);
  final scored = <(ContentItem, int)>[];
  for (final c in content) {
    if (!c.hasCoordinates) continue;
    final m = GeoMath.distanceMeters(
        loc.latitude!, loc.longitude!, c.latitude, c.longitude);
    if (m > radiusMeters) continue;
    final hasContent =
        (c.audioUrl?.isNotEmpty ?? false) || (c.text?.isNotEmpty ?? false);
    if (!hasContent) continue;
    // Only link narration that's actually ABOUT this place: a name match, or a
    // relevant category that is essentially co-located (≤250 m). A neighbor's
    // narration (e.g. a lake near a boat ramp) must NOT get attached, or the
    // location plays the wrong place's audio.
    final nameMatch = _nameOverlap(loc.name, c.title);
    final categoryMatch = relevant.contains(c.category);
    if (!nameMatch && !(categoryMatch && m <= 250)) continue;
    var score = -(m ~/ 50);
    if (nameMatch) score += 500;
    if (categoryMatch) score += 200;
    if (c.audioUrl?.isNotEmpty ?? false) score += 120;
    score += c.basePriority;
    scored.add((c, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  final ids = <String>[];
  final audio = <String>[];
  for (final (c, _) in scored) {
    ids.add(c.id);
    if (c.audioUrl?.isNotEmpty ?? false) audio.add(c.audioUrl!);
  }
  return LocationNarrationLinks(ids, audio);
}

bool _nameOverlap(String a, String b) {
  final x = a.toLowerCase().trim();
  final y = b.toLowerCase().trim();
  if (x.isEmpty || y.isEmpty) return false;
  return x.contains(y) || y.contains(x);
}

/// Composes a short fallback script from what we know about a location.
String composeLocationScript(MasterLocation loc) {
  final desc = (loc.description ?? '').trim();
  if (desc.isNotEmpty) return desc;
  final place = loc.placeLine;
  final where = place == null ? '' : ' in $place';
  return '${loc.name} is a ${loc.type.label.toLowerCase()}$where. '
      "Keep exploring and I'll tell you more about what's around you.";
}

/// Resolves the best narration for a master [loc], attaching existing
/// `location_content` narration when it matches:
///  1. the location's own recorded audio (`audio_files`);
///  2. the nearest matching `location_content` within [radiusMeters] — a
///     name/category match with audio wins, then text;
///  3. a composed script for TTS.
LocationNarration resolveLocationNarration(
  MasterLocation loc,
  List<ContentItem> content, {
  double radiusMeters = 1609.344, // 1 mile
}) {
  if (loc.audioFiles.isNotEmpty) {
    return LocationNarration(
      title: loc.name,
      text: composeLocationScript(loc),
      audioUrl: loc.audioFiles.first,
    );
  }

  final relevant = relevantCategories(loc.type);
  ContentItem? best;
  int bestScore = -1 << 30;
  if (loc.hasCoordinates) {
    for (final c in content) {
      if (!c.hasCoordinates) continue;
      final m = GeoMath.distanceMeters(
          loc.latitude!, loc.longitude!, c.latitude, c.longitude);
      if (m > radiusMeters) continue;
      final hasContent =
          (c.audioUrl?.isNotEmpty ?? false) || (c.text?.isNotEmpty ?? false);
      if (!hasContent) continue;
      // Only borrow a nearby narration when it's actually about THIS place:
      // a name match, or a category relevant to this location type. A purely
      // proximity-based match would play a neighbor's (wrong) narration.
      final nameMatch = _nameOverlap(loc.name, c.title);
      final categoryMatch = relevant.contains(c.category);
      if (!nameMatch && !categoryMatch) continue;
      var score = -(m ~/ 50); // nearer is better
      if (nameMatch) score += 500;
      if (categoryMatch) score += 200;
      if (c.audioUrl?.isNotEmpty ?? false) score += 120;
      score += c.basePriority;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
  }

  if (best != null) {
    final text = (best.text?.trim().isNotEmpty ?? false)
        ? best.text!.trim()
        : composeLocationScript(loc);
    return LocationNarration(
      title: loc.name,
      text: text,
      audioUrl: best.audioUrl,
      sourceContentId: best.id,
    );
  }

  return LocationNarration(title: loc.name, text: composeLocationScript(loc));
}
