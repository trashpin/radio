// Widget tests for the Favorites capability and the Destination Details screen.
//
// Providers are overridden with sample data so both behaviors can be verified
// without a live Supabase connection.

import 'package:explorer_os_mobile/features/destinations/presentation/destination_details_screen.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/destinations_screen.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = [
  Destination(
    id: '1',
    name: 'Yosemite',
    location: 'California',
    category: 'park',
    description: 'Granite cliffs and giant sequoias.',
    featured: true,
  ),
  Destination(
    id: '2',
    name: 'Juniper Springs',
    location: 'Ocala National Forest',
    category: 'trail',
  ),
];

void main() {
  testWidgets('tapping the heart adds a Favorites section', (tester) async {
    // Tall surface so every list section is laid out (avoids lazy-list
    // off-screen children).
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [destinationsProvider.overrideWith((ref) async => _sample)],
        child: const MaterialApp(home: DestinationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // No favorites yet.
    expect(find.text('Favorites'), findsNothing);

    // Tap the first (featured) heart to favorite it.
    await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
    await tester.pumpAndSettle();

    // The heart fills and the Favorites section appears.
    expect(find.byIcon(Icons.favorite_rounded), findsWidgets);
    expect(find.text('Favorites'), findsOneWidget);
  });

  testWidgets('details screen shows the destination info', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [destinationsProvider.overrideWith((ref) async => _sample)],
        child: const MaterialApp(
          home: DestinationDetailsScreen(destinationId: '1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Yosemite'), findsOneWidget);
    expect(find.text('California'), findsOneWidget);
    expect(find.text('Granite cliffs and giant sequoias.'), findsOneWidget);
    expect(find.text('View on Map'), findsOneWidget);
  });

  testWidgets('details screen handles an unknown id gracefully',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [destinationsProvider.overrideWith((ref) async => _sample)],
        child: const MaterialApp(
          home: DestinationDetailsScreen(destinationId: 'missing'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Destination not found.'), findsOneWidget);
  });
}
