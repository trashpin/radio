import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/discover_area/models/area_content_block.dart';
import 'package:explorer_os_mobile/features/discover_area/models/audio_experience_sequence.dart';
import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/discover_area/models/narratable_item.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

DiscoveryArea _area({String? shortDescription, String? narrationScript}) =>
    DiscoveryArea(
      location: MasterLocation.fromJson({
        'id': 'area-1',
        'name': 'Historic Downtown Ocala',
        'category': 'area',
        'latitude': 29.2,
        'longitude': -82.1,
        'trigger_radius': 800,
        'short_description': shortDescription,
        'narration_script': narrationScript,
      }),
      distanceMeters: 0,
    );

AreaContentBlock _block(String title, {String category = 'history'}) => AreaContentBlock(
      id: title,
      locationId: 'area-1',
      categoryToken: category,
      title: title,
      narrationScript: '$title script',
    );

Species _species(String name) =>
    Species(id: name, category: 'animals', commonName: name, description: '$name description');

void main() {
  group('buildAudioExperienceSequence', () {
    test('assembles the full spec order: intro, history, wildlife, nature, '
        'facts, attractions', () {
      final area = _area(
        shortDescription: 'Welcome intro text.',
        narrationScript: 'Some distinct facts text.',
      );
      final sequence = buildAudioExperienceSequence(
        area: area,
        historyBlocks: [_block('Early Settlement')],
        wildlifeSpecies: [_species('Gopher Tortoise')],
        natureBlocks: [_block('Silver River', category: 'nature')],
        attractions: const [],
        locationContentItems: const [],
      );
      expect(sequence.map((i) => i.title), [
        'Welcome to Historic Downtown Ocala',
        'Early Settlement',
        'Gopher Tortoise',
        'Silver River',
        'Interesting Facts',
      ]);
    });

    test('omits the intro section entirely when there is no short '
        'introduction', () {
      final area = _area();
      final sequence = buildAudioExperienceSequence(
        area: area,
        historyBlocks: [_block('Early Settlement')],
        wildlifeSpecies: const [],
        natureBlocks: const [],
        attractions: const [],
        locationContentItems: const [],
      );
      expect(sequence.map((i) => i.title), ['Early Settlement']);
    });

    test('omits Interesting Facts when it is identical to the intro', () {
      final area = _area(
        shortDescription: 'Same text.',
        narrationScript: 'Same text.',
      );
      final sequence = buildAudioExperienceSequence(
        area: area,
        historyBlocks: const [],
        wildlifeSpecies: const [],
        natureBlocks: const [],
        attractions: const [],
        locationContentItems: const [],
      );
      expect(sequence, hasLength(1)); // just the intro, no duplicate facts
    });

    test('caps wildlife to wildlifeLimit', () {
      final area = _area(shortDescription: 'Intro.');
      final sequence = buildAudioExperienceSequence(
        area: area,
        historyBlocks: const [],
        wildlifeSpecies: [
          _species('A'),
          _species('B'),
          _species('C'),
          _species('D'),
          _species('E'),
        ],
        natureBlocks: const [],
        attractions: const [],
        locationContentItems: const [],
        wildlifeLimit: 2,
      );
      final wildlifeTitles = sequence.map((i) => i.title).where(
            (t) => ['A', 'B', 'C', 'D', 'E'].contains(t),
          );
      expect(wildlifeTitles, hasLength(2));
    });

    test('drops items with no narration at all rather than playing dead air',
        () {
      final area = _area(shortDescription: 'Intro.');
      const blankBlock = AreaContentBlock(
        id: 'blank',
        locationId: 'area-1',
        categoryToken: 'history',
        title: 'Blank Block',
        // no narrationScript, no audioUrl
      );
      final sequence = buildAudioExperienceSequence(
        area: area,
        historyBlocks: const [blankBlock],
        wildlifeSpecies: const [],
        natureBlocks: const [],
        attractions: const [],
        locationContentItems: const [],
      );
      expect(sequence.any((i) => i.title == 'Blank Block'), isFalse);
    });

    test('empty area with nothing at all produces an empty sequence', () {
      final area = _area();
      final sequence = buildAudioExperienceSequence(
        area: area,
        historyBlocks: const [],
        wildlifeSpecies: const [],
        natureBlocks: const [],
        attractions: const [],
        locationContentItems: const [],
      );
      expect(sequence, isEmpty);
    });
  });

  group('NarratableItem', () {
    test('hasAudio/hasNarration reflect what is actually present', () {
      const withAudio = NarratableItem(title: 'A', audioUrl: 'https://x/a.mp3');
      const withScript = NarratableItem(title: 'B', script: 'text');
      const withNeither = NarratableItem(title: 'C');

      expect(withAudio.hasAudio, isTrue);
      expect(withAudio.hasNarration, isTrue);
      expect(withScript.hasAudio, isFalse);
      expect(withScript.hasNarration, isTrue);
      expect(withNeither.hasNarration, isFalse);
    });

    test('fromContentBlock carries title/audio/script through', () {
      final block = _block('Railroads');
      final item = NarratableItem.fromContentBlock(block);
      expect(item.title, 'Railroads');
      expect(item.script, 'Railroads script');
    });
  });
}
