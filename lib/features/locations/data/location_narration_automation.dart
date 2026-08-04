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
  if (!loc.hasCoordinates) return const
