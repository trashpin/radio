import 'package:explorer_os_mobile/shared/design/category_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('categoryIconFor — spec mapping', () {
    final cases = <String, IconData>{
      'Festivals': Icons.celebration_rounded,
      'Spring': Icons.water_drop_rounded,
      'State Park': Icons.park_rounded,
      'Trail': Icons.hiking_rounded,
      'Birds': Icons.flutter_dash_rounded,
      'Wildlife Viewing': Icons.pets_rounded,
      'Wildflowers': Icons.local_florist_rounded,
      'Historic Site': Icons.account_balance_rounded,
      'Live Music': Icons.music_note_rounded,
      'Horses & Equestrian': Icons.emoji_nature_rounded,
      'Cars & Trucks': Icons.directions_car_rounded,
      'Arts & Culture': Icons.palette_rounded,
      'Family': Icons.family_restroom_rounded,
      'Shopping': Icons.shopping_bag_rounded,
      'Farmers Market': Icons.shopping_basket_rounded,
      'Fishing': Icons.phishing_rounded,
      'Boating': Icons.directions_boat_rounded,
      'Photography': Icons.camera_alt_rounded,
      'Nightlife': Icons.nightlight_rounded,
      'Adventure': Icons.landscape_rounded,
      'Restaurant': Icons.restaurant_rounded,
      'Theater': Icons.theater_comedy_rounded,
      'Museum': Icons.museum_rounded,
      'Campground': Icons.cabin_rounded,
      'Swimming': Icons.pool_rounded,
      'Scenic Overlook': Icons.wb_sunny_rounded,
      'Free Things': Icons.money_off_rounded,
    };

    cases.forEach((category, expected) {
      test('"$category" -> $expected', () {
        expect(categoryIconFor(category), expected);
      });
    });
  });

  test('a bare "Gem" resolves to the diamond icon, distinct from a food category', () {
    expect(categoryIconFor('Hidden Gem'), Icons.diamond_rounded);
    expect(categoryIconFor('Restaurant'), isNot(Icons.diamond_rounded));
  });

  test('museum is checked before the more generic historic keyword', () {
    // "Historic Site" alone has no "museum" substring, so this just confirms
    // the two don't collide on a record that IS explicitly a museum.
    expect(categoryIconFor('Museum'), Icons.museum_rounded);
    expect(categoryIconFor('Historic District'), Icons.account_balance_rounded);
  });

  test('unrecognized or missing categories still get a real icon, never null', () {
    expect(categoryIconFor('Some Totally New Category'), Icons.place_rounded);
    expect(categoryIconFor(null), Icons.place_rounded);
    expect(categoryIconFor(''), Icons.place_rounded);
  });

  test('matching is case-insensitive', () {
    expect(categoryIconFor('FESTIVAL'), Icons.celebration_rounded);
    expect(categoryIconFor('spring'), Icons.water_drop_rounded);
  });

  group('CategoryImagePlaceholder', () {
    testWidgets('renders the resolved icon for a known category', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CategoryImagePlaceholder('Festivals')),
      );
      expect(find.byIcon(Icons.celebration_rounded), findsOneWidget);
    });

    testWidgets('still renders a real icon for an unrecognized category', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: CategoryImagePlaceholder('Something New')),
      );
      expect(find.byIcon(Icons.place_rounded), findsOneWidget);
    });

    testWidgets('a categoryPhotoUrl renders a real image instead of the icon tile',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CategoryImagePlaceholder(
            'Festivals',
            categoryPhotoUrl: 'https://example.com/festival.jpg',
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.celebration_rounded), findsNothing);
    });

    testWidgets('a null/empty categoryPhotoUrl falls through to the icon tile',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CategoryImagePlaceholder('Festivals', categoryPhotoUrl: ''),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.celebration_rounded), findsOneWidget);
    });
  });

  group('categoryVisualKeyFor — canonical bucket keys', () {
    test('groups keyword variants into the same stable key', () {
      expect(categoryVisualKeyFor('Festivals'), 'festivals');
      expect(categoryVisualKeyFor('firework show'), 'festivals');
      expect(categoryVisualKeyFor('Live Music'), 'live_music');
      expect(categoryVisualKeyFor('concert'), 'live_music');
      expect(categoryVisualKeyFor('Nightlife'), 'nightlife');
      expect(categoryVisualKeyFor('Restaurant'), 'food');
      expect(categoryVisualKeyFor('Hidden Gem'), 'gems');
    });

    test('unrecognized categories resolve to the general fallback key', () {
      expect(categoryVisualKeyFor('Something Totally New'), 'general');
      expect(categoryVisualKeyFor(null), 'general');
    });

    test('categoryVisualKeys is non-empty and every value is unique', () {
      expect(categoryVisualKeys, isNotEmpty);
      expect(categoryVisualKeys.toSet().length, categoryVisualKeys.length);
    });
  });
}
