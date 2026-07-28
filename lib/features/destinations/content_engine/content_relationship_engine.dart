import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/destinations/content_engine/content_data_source.dart';
import 'package:explorer_os_mobile/features/destinations/content_engine/models/destination_content.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';

// --- Pure classification / assembly (unit-tested) ---------------------------

const _wildlifeTokens = [
  'animal', 'mammal', 'bird', 'reptile', 'amphibian', 'fish', 'wildlife',
  'insect',
];
const _plantTokens = [
  'plant', 'tree', 'wildflower', 'flower', 'mushroom', 'fern', 'grass',
];

bool isWildlifeCategory(String? category) {
  final c = (category ?? '').toLowerCase();
  return _wildlifeTokens.any(c.contains);
}

bool isPlantCategory(String? category) {
  final c = (category ?? '').toLowerCase();
  return _plantTokens.any(c.contains);
}

List<Species> filterWildlife(List<Species> all) =>
    all.where((s) => isWildlifeCategory(s.category)).toList();

List<Species> filterPlants(List<Species> all) =>
    all.where((s) => isPlantCategory(s.category)).toList();

/// Groups a destination's media assets into hero / gallery / videos / audio.
/// The hero falls back to the destination row's own `hero_image`.
DestinationMedia assembleMedia(List<MediaAsset> assets, DestinationRef d) {
  final images = assets.where((a) => a.mediaType == MediaType.image).toList();
  final heroAssets = images.where((a) => a.isHero).toList();

  MediaAsset? hero;
  List<MediaAsset> gallery;
  if (heroAssets.isNotEmpty) {
    hero = heroAssets.first;
    gallery = images.where((a) => a.id != hero!.id).toList();
  } else {
    gallery = List.of(images);
    if ((d.heroImage ?? '').isNotEmpty) {
      hero = MediaAsset(
        id: 'dest-hero-${d.id}',
        recordId: d.id,
        recordType: 'destination',
        destinationId: d.id,
        mediaType: MediaType.image,
        publicUrl: d.heroImage,
        thumbnail: d.heroImage,
        title: '${d.name} hero',
        isHero: true,
      );
    }
  }

  return DestinationMedia(
    hero: hero,
    gallery: gallery,
    videos: assets.where((a) => a.mediaType == MediaType.video).toList(),
    audio: assets.where((a) => a.isAudioLike).toList(),
  );
}

/// Sorts nearby items by distance from the destination (nearest first) when
/// coordinates are known.
List<NearbyItem> sortNearby(List<NearbyItem> items, DestinationRef d) {
  if (!d.hasCoordinates) return items;
  final copy = List.of(items);
  copy.sort((a, b) {
    final da = GeoMath.distanceMeters(
        d.latitude!, d.longitude!, a.latitude, a.longitude);
    final db = GeoMath.distanceMeters(
        d.latitude!, d.longitude!, b.latitude, b.longitude);
    return da.compareTo(db);
  });
  return copy;
}

// --- The engine -------------------------------------------------------------

/// The Content Relationship Engine.
///
/// Every piece of ExplorerOS content is linked to a single `destination_code`.
/// This engine resolves a code to its destination and retrieves all related
/// content through one API — so modules never store independent relationships.
class ContentRelationshipEngine {
  const ContentRelationshipEngine(this.source);

  final ContentDataSource source;

  /// Resolves a `destination_code` to its [DestinationRef], or null.
  Future<DestinationRef?> resolveDestination(String destinationCode) async {
    final row = await source.findDestination(destinationCode);
    return row == null ? null : DestinationRef.fromJson(row);
  }

  /// All media for a destination, grouped by role.
  Future<DestinationMedia> getDestinationMedia(String destinationCode) async {
    final d = await resolveDestination(destinationCode);
    if (d == null) return DestinationMedia.empty;
    return assembleMedia(await source.media(d), d);
  }

  /// Approved/published narration rows for a destination.
  Future<List<Map<String, dynamic>>> getDestinationNarration(
      String destinationCode) async {
    final d = await resolveDestination(destinationCode);
    if (d == null) return const [];
    return source.narration(d);
  }

  /// Stories linked to a destination.
  Future<List<Map<String, dynamic>>> getDestinationStories(
      String destinationCode) async {
    final d = await resolveDestination(destinationCode);
    if (d == null) return const [];
    return source.stories(d);
  }

  /// Wildlife (animals, birds, reptiles, amphibians, fish) for a destination.
  Future<List<Species>> getDestinationWildlife(String destinationCode) async {
    final d = await resolveDestination(destinationCode);
    if (d == null) return const [];
    return filterWildlife(await source.species(d));
  }

  /// Plants (plants, trees, wildflowers) for a destination.
  Future<List<Species>> getDestinationPlants(String destinationCode) async {
    final d = await resolveDestination(destinationCode);
    if (d == null) return const [];
    return filterPlants(await source.species(d));
  }

  /// Background music (songs) for a destination.
  Future<List<Map<String, dynamic>>> getDestinationMusic(
      String destinationCode) async {
    final d = await resolveDestination(destinationCode);
    if (d == null) return const [];
    return source.music(d);
  }

  /// THE master function: loads everything for a destination in one object.
  ///
  /// Resolves the code once, then fetches every content type concurrently and
  /// assembles a single [DestinationExperience].
  Future<DestinationExperience> loadDestinationExperience(
      String destinationCode) async {
    final d = await resolveDestination(destinationCode);
    if (d == null) return DestinationExperience.notFound(destinationCode);

    final results = await Future.wait([
      source.media(d),
      source.species(d),
      source.narration(d),
      source.stories(d),
      source.music(d),
      source.nearby(d),
      source.historicalEvents(d),
    ]);

    final assets = results[0] as List<MediaAsset>;
    final allSpecies = results[1] as List<Species>;

    return DestinationExperience(
      destination: d,
      media: assembleMedia(assets, d),
      wildlife: filterWildlife(allSpecies),
      plants: filterPlants(allSpecies),
      narration: results[2] as List<Map<String, dynamic>>,
      stories: results[3] as List<Map<String, dynamic>>,
      music: results[4] as List<Map<String, dynamic>>,
      nearby: sortNearby(results[5] as List<NearbyItem>, d),
      historicalEvents: results[6] as List<Map<String, dynamic>>,
    );
  }
}
