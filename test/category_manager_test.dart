import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/admin/categories/location_category.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

void main() {
  group('LocationCategory', () {
    test('fromJson/toWrite round-trip', () {
      final c = LocationCategory.fromJson({
        'id': '1',
        'slug': 'brewery',
        'label': 'Brewery',
        'icon': 'restaurant',
        'sort_order': 30,
        'active': true,
      });
      expect(c.slug, 'brewery');
      expect(c.label, 'Brewery');
      expect(c.sortOrder, 30);
      expect(c.toWrite(), {
        'slug': 'brewery',
        'label': 'Brewery',
        'icon': 'restaurant',
        'sort_order': 30,
        'active': true,
      });
    });

    test('missing fields default sensibly', () {
      final c = LocationCategory.fromJson({'id': '1'});
      expect(c.slug, '');
      expect(c.label, '');
      expect(c.icon, isNull);
      expect(c.sortOrder, 0);
      expect(c.active, isTrue);
    });
  });

  group('combinedCategoryOptions', () {
    test('with no custom categories, returns exactly the built-in taxonomy',
        () {
      final options = combinedCategoryOptions(const []);
      expect(options.length, LocationType.values.length);
      expect(options.every((o) => !o.isCustom), isTrue);
      // Built-in order is preserved.
      expect(options.first.id, LocationType.values.first.id);
    });

    test('active custom categories are appended after built-ins', () {
      final custom = [
        const LocationCategory(id: '1', slug: 'brewery', label: 'Brewery'),
        const LocationCategory(id: '2', slug: 'winery', label: 'Winery'),
      ];
      final options = combinedCategoryOptions(custom);
      expect(options.length, LocationType.values.length + 2);
      final ids = options.map((o) => o.id).toList();
      expect(ids, contains('brewery'));
      expect(ids, contains('winery'));
      // Custom ones are flagged.
      expect(
        options.firstWhere((o) => o.id == 'brewery').isCustom,
        isTrue,
      );
    });

    test('inactive custom categories are excluded', () {
      final custom = [
        const LocationCategory(
          id: '1',
          slug: 'brewery',
          label: 'Brewery',
          active: false,
        ),
      ];
      final options = combinedCategoryOptions(custom);
      expect(options.any((o) => o.id == 'brewery'), isFalse);
    });

    test('a custom slug matching a built-in id is not duplicated', () {
      // If an admin (or a bad import) adds a custom row whose slug collides
      // with a built-in LocationType id, the built-in wins — no duplicate
      // entries in the picker.
      final custom = [
        const LocationCategory(id: '1', slug: 'museum', label: 'Museum++'),
      ];
      final options = combinedCategoryOptions(custom);
      expect(options.where((o) => o.id == 'museum').length, 1);
      expect(options.firstWhere((o) => o.id == 'museum').isCustom, isFalse);
    });

    test('custom categories are sorted by sortOrder then label', () {
      final custom = [
        const LocationCategory(
            id: '1', slug: 'z_one', label: 'Zebra', sortOrder: 5),
        const LocationCategory(
            id: '2', slug: 'a_one', label: 'Apple', sortOrder: 1),
        const LocationCategory(
            id: '3', slug: 'a_two', label: 'Banana', sortOrder: 1),
      ];
      final options = combinedCategoryOptions(custom);
      final customOnly =
          options.where((o) => o.isCustom).map((o) => o.id).toList();
      expect(customOnly, ['a_one', 'a_two', 'z_one']);
    });
  });
}
