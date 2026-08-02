// Widget tests for the Discover This Area screen — overrides
// currentDiscoveryAreaProvider so we can deterministically drive both the
// "no area detected" state and the populated hero + category grid state
// without a live GPS fix or Supabase connection.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/discover_area/models/area_discovery_category.dart';
import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/discover_area_screen.dart';
import 'package:explorer_os_mobile/features/discover_area/providers/discovery_area_provider.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

DiscoveryArea _sampleArea() => DiscoveryArea(
      location: MasterLocation.fromJson({
        'id': '1',
        'name': 'Historic Downtown Ocala',
        'category': 'area',
        'latitude': 29.2,
        'longitude': -82.1,
        'trigger_radius': 800,
        'short_description': 'The heart of Marion County.',
        'estimated_listening_minutes': 12,
        'images': ['https://example.com/hero.jpg'],
      }),
      distanceMeters: 0,
    );

void main() {
  testWidgets('shows the "no area detected" empty state when null',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentDiscoveryAreaProvider.overrideWithValue(null)],
        child: const MaterialApp(home: DiscoverAreaScreen()),
      ),
    );
    expect(find.text('No area detected here yet'), findsOneWidget);
    expect(find.text('Explore'), findsNothing);
  });

  testWidgets('shows area name, intro, listening time, and every category',
      (tester) async {
    // Tall surface so the lazy category grid lays out fully in the test.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentDiscoveryAreaProvider.overrideWithValue(_sampleArea()),
        ],
        child: const MaterialApp(home: DiscoverAreaScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The area name appears in both the hero title and the "You're here" badge.
    expect(find.text('Historic Downtown Ocala'), findsWidgets);
    expect(find.text('The heart of Marion County.'), findsOneWidget);
    expect(find.text('~12 min'), findsOneWidget);
    expect(find.text("You're here"), findsOneWidget);

    for (final cat in areaDiscoveryCategories) {
      expect(find.text(cat.label), findsWidgets,
          reason: '${cat.label} category should render');
    }
  });

  testWidgets('tapping a category navigates to its placeholder screen',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentDiscoveryAreaProvider.overrideWithValue(_sampleArea()),
        ],
        child: const MaterialApp(home: DiscoverAreaScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final history = find.text('History');
    await tester.ensureVisible(history);
    await tester.pumpAndSettle();
    await tester.tap(history);
    await tester.pumpAndSettle();

    expect(find.text('History for Historic Downtown Ocala'), findsOneWidget);
  });
}
