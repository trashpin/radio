import 'package:explorer_os_mobile/features/ocala_forest/discover/models/discovery_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiscoveryGroup', () {
    test('fromId round-trips every group id', () {
      for (final g in DiscoveryGroup.values) {
        expect(DiscoveryGroup.fromId(g.id), g);
      }
    });

    test('fromId returns null for an unknown id', () {
      expect(DiscoveryGroup.fromId('not_a_real_category'), isNull);
      expect(DiscoveryGroup.fromId(null), isNull);
    });

    test('every group except other has at least one subtype', () {
      for (final g in DiscoveryGroup.values) {
        if (g == DiscoveryGroup.other) {
          expect(g.subtypes, isEmpty);
        } else {
          expect(g.subtypes, isNotEmpty);
        }
      }
    });

    test('fromSpeciesCategory maps the app-wide species taxonomy sensibly', () {
      expect(DiscoveryGroup.fromSpeciesCategory('birds'), DiscoveryGroup.birds);
      expect(DiscoveryGroup.fromSpeciesCategory('mammals'), DiscoveryGroup.wildlife);
      expect(DiscoveryGroup.fromSpeciesCategory('reptiles'), DiscoveryGroup.wildlife);
      expect(DiscoveryGroup.fromSpeciesCategory('trees'), DiscoveryGroup.plantsNature);
      expect(DiscoveryGroup.fromSpeciesCategory('springs'), DiscoveryGroup.water);
      expect(DiscoveryGroup.fromSpeciesCategory('historic_sites'), DiscoveryGroup.history);
      expect(DiscoveryGroup.fromSpeciesCategory('something_unmapped'), DiscoveryGroup.other);
    });
  });
}
