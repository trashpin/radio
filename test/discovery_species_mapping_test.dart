import 'package:explorer_os_mobile/features/ocala_forest/discover/models/discovery_category.dart';
import 'package:explorer_os_mobile/features/ocala_forest/discover/models/discovery_species_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('speciesCategoriesFor', () {
    test('maps wildlife subtypes to their exact species category', () {
      expect(speciesCategoriesFor(DiscoveryGroup.wildlife, 'Tracks/Signs'), ['animal_tracks']);
      expect(speciesCategoriesFor(DiscoveryGroup.wildlife, 'Reptile'), ['reptiles']);
      expect(speciesCategoriesFor(DiscoveryGroup.wildlife, 'Amphibian'), ['amphibians']);
      expect(speciesCategoriesFor(DiscoveryGroup.wildlife, 'Insect'), ['insects']);
    });

    test('birds always maps to the birds category regardless of subtype', () {
      expect(speciesCategoriesFor(DiscoveryGroup.birds, 'Bird'), ['birds']);
      expect(speciesCategoriesFor(DiscoveryGroup.birds, 'Other Bird-Related Discovery'), ['birds']);
    });

    test('geology has no matching species category (falls straight to photo)', () {
      expect(speciesCategoriesFor(DiscoveryGroup.geology, 'Rock'), isEmpty);
    });

    test('other has no subtypes and no matching species category', () {
      expect(speciesCategoriesFor(DiscoveryGroup.other, null), isEmpty);
    });

    test('plants & nature subtypes map to distinct categories', () {
      expect(speciesCategoriesFor(DiscoveryGroup.plantsNature, 'Tree'), ['trees']);
      expect(speciesCategoriesFor(DiscoveryGroup.plantsNature, 'Mushroom'), ['mushrooms']);
      expect(speciesCategoriesFor(DiscoveryGroup.plantsNature, 'Wildflower'), ['wildflowers']);
    });

    test('every DiscoveryGroup value is handled without throwing', () {
      for (final g in DiscoveryGroup.values) {
        expect(() => speciesCategoriesFor(g, null), returnsNormally);
        for (final s in g.subtypes) {
          expect(() => speciesCategoriesFor(g, s), returnsNormally);
        }
      }
    });
  });
}
