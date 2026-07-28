import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/destinations/content_engine/content_data_source.dart';
import 'package:explorer_os_mobile/features/destinations/content_engine/content_relationship_engine.dart';
import 'package:explorer_os_mobile/features/destinations/content_engine/models/destination_content.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';

/// A deterministic in-memory data source: everything is linked to the single
/// destination `FLNF0001` (id `dest1`).
class FakeContentDataSource implements ContentDataSource {
  @override
  Future<Map<String, dynamic>?> findDestination(String code) async {
    if (code == 'FLNF0001' || code == 'dest1' || code == 'ocala') {
      return {
        'destination_code': 'FLNF0001',
        'destination_id': 'dest1',
        'name': 'Ocala National Forest',
        'slug': 'ocala',
        'hero_image': 'https://cdn/dest-hero.jpg',
        'latitude': 29.1872,
        'longitude': -81.7137,
      };
    }
    return null;
  }

  @override
  Future<List<MediaAsset>> media(DestinationRef d) async => [
        MediaAsset(
            id: 'img-hero',
            destinationId: d.id,
            mediaType: MediaType.image,
            isHero: true,
            publicUrl: 'https://cdn/hero.jpg'),
        MediaAsset(
            id: 'img-g1',
            destinationId: d.id,
            mediaType: MediaType.image,
            publicUrl: 'https://cdn/g1.jpg'),
        MediaAsset(
            id: 'vid1',
            destinationId: d.id,
            mediaType: MediaType.video,
            publicUrl: 'https://cdn/v1.mp4'),
        MediaAsset(
            id: 'aud1',
            destinationId: d.id,
            mediaType: MediaType.audio,
            publicUrl: 'https://cdn/a1.mp3'),
      ];

  @override
  Future<List<Species>> species(DestinationRef d) async => const [
        Species(id: 'sp1', category: 'birds', commonName: 'Bald Eagle'),
        Species(id: 'sp2', category: 'trees', commonName: 'Sand Pine'),
        Species(id: 'sp3', category: 'reptiles', commonName: 'Gopher Tortoise'),
        Species(id: 'sp4', category: 'wildflowers', commonName: 'Blazing Star'),
      ];

  @override
  Future<List<Map<String, dynamic>>> narration(DestinationRef d) async =>
      [{'id': 'n1', 'destination_id': d.id}];

  @override
  Future<List<Map<String, dynamic>>> stories(DestinationRef d) async =>
      [{'id': 's1'}, {'id': 's2'}];

  @override
  Future<List<Map<String, dynamic>>> music(DestinationRef d) async =>
      [{'id': 'song1', 'park_code': d.parkKey}];

  @override
  Future<List<NearbyItem>> nearby(DestinationRef d) async => const [
        // Deliberately out of order to test distance sorting.
        NearbyItem(
            id: 'far',
            category: 'trails',
            name: 'Far Trail',
            latitude: 29.30,
            longitude: -81.71),
        NearbyItem(
            id: 'near',
            category: 'springs',
            name: 'Near Spring',
            latitude: 29.188,
            longitude: -81.713),
      ];

  @override
  Future<List<Map<String, dynamic>>> historicalEvents(DestinationRef d) async =>
      [{'id': 'h1'}];
}

void main() {
  final engine = ContentRelationshipEngine(FakeContentDataSource());

  group('classification', () {
    test('wildlife vs plant categories', () {
      expect(isWildlifeCategory('birds'), isTrue);
      expect(isWildlifeCategory('reptiles'), isTrue);
      expect(isWildlifeCategory('trees'), isFalse);
      expect(isPlantCategory('wildflowers'), isTrue);
      expect(isPlantCategory('trees'), isTrue);
      expect(isPlantCategory('fish'), isFalse);
    });
  });

  group('assembleMedia', () {
    const d = DestinationRef(
        code: 'C', id: 'x', name: 'X', heroImage: 'https://cdn/fallback.jpg');

    test('uses an is_hero asset and excludes it from the gallery', () {
      final media = assembleMedia([
        MediaAsset(id: 'h', mediaType: MediaType.image, isHero: true, publicUrl: 'u'),
        MediaAsset(id: 'g', mediaType: MediaType.image, publicUrl: 'u2'),
      ], d);
      expect(media.hero!.id, 'h');
      expect(media.gallery.map((a) => a.id), ['g']);
    });

    test('falls back to the destination hero image', () {
      final media = assembleMedia([
        MediaAsset(id: 'g', mediaType: MediaType.image, publicUrl: 'u2'),
      ], d);
      expect(media.hero, isNotNull);
      expect(media.hero!.publicUrl, 'https://cdn/fallback.jpg');
      expect(media.gallery.length, 1); // the non-hero image stays in gallery
    });
  });

  group('helper functions', () {
    test('getDestinationMedia groups roles', () async {
      final m = await engine.getDestinationMedia('FLNF0001');
      expect(m.hero!.id, 'img-hero');
      expect(m.gallery.map((a) => a.id), ['img-g1']);
      expect(m.videos.length, 1);
      expect(m.audio.length, 1);
    });

    test('getDestinationWildlife / getDestinationPlants split species', () async {
      final wildlife = await engine.getDestinationWildlife('FLNF0001');
      final plants = await engine.getDestinationPlants('FLNF0001');
      expect(wildlife.map((s) => s.commonName),
          containsAll(['Bald Eagle', 'Gopher Tortoise']));
      expect(plants.map((s) => s.commonName),
          containsAll(['Sand Pine', 'Blazing Star']));
      expect(wildlife.length, 2);
      expect(plants.length, 2);
    });

    test('narration / stories / music helpers', () async {
      expect((await engine.getDestinationNarration('FLNF0001')).length, 1);
      expect((await engine.getDestinationStories('FLNF0001')).length, 2);
      expect((await engine.getDestinationMusic('FLNF0001')).length, 1);
    });

    test('unknown code yields empty results', () async {
      expect(await engine.getDestinationWildlife('NOPE'), isEmpty);
      expect((await engine.getDestinationMedia('NOPE')).isEmpty, isTrue);
    });
  });

  group('loadDestinationExperience', () {
    test('assembles one object with all related content', () async {
      final exp = await engine.loadDestinationExperience('FLNF0001');
      expect(exp.isFound, isTrue);
      expect(exp.destination.code, 'FLNF0001');
      expect(exp.destination.name, 'Ocala National Forest');
      expect(exp.media.hero!.id, 'img-hero');
      expect(exp.media.gallery.length, 1);
      expect(exp.media.videos.length, 1);
      expect(exp.wildlife.length, 2);
      expect(exp.plants.length, 2);
      expect(exp.narration.length, 1);
      expect(exp.stories.length, 2);
      expect(exp.music.length, 1);
      expect(exp.historicalEvents.length, 1);
      // Nearby sorted nearest-first.
      expect(exp.nearby.first.id, 'near');
      expect(exp.counts['wildlife'], 2);
    });

    test('unknown code returns a not-found experience', () async {
      final exp = await engine.loadDestinationExperience('MISSING');
      expect(exp.isFound, isFalse);
      expect(exp.wildlife, isEmpty);
      expect(exp.nearby, isEmpty);
    });
  });
}
