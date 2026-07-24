// Widget tests for the Explore (destinations) screen.
//
// These override the providers so we can deterministically drive each state
// (list, empty, error) and the search/category filtering WITHOUT a live
// Supabase connection — proving the screen and filter logic render correctly.

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/destinations_screen.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destination_filters.dart';
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
    featured: true,
  ),
  Destination(
    id: '2',
    name: 'Blue Ridge Parkway',
    location: 'North Carolina',
    category: 'scenic',
  ),
];

void main() {
  testWidgets('shows Featured + Popular sections with loaded destinations',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [destinationsProvider.overrideWith((ref) async => _sample)],
        child: const MaterialApp(home: DestinationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Featured Destinations'), findsOneWidget);
    expect(find.text('Popular Near You'), findsOneWidget);
    expect(find.text('Yosemite'), findsWidgets);
    expect(find.text('Blue Ridge Parkway'), findsWidgets);
  });

  testWidgets('shows "No destinations found." when the table is empty',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          destinationsProvider.overrideWith((ref) async => const <Destination>[])
        ],
        child: const MaterialApp(home: DestinationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No destinations found.'), findsOneWidget);
  });

  testWidgets('search query filters the list', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          destinationsProvider.overrideWith((ref) async => _sample),
          destinationQueryProvider.overrideWith((ref) => 'blue'),
        ],
        child: const MaterialApp(home: DestinationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Search active → flat "Results" list, featured hidden.
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Blue Ridge Parkway'), findsOneWidget);
    expect(find.text('Yosemite'), findsNothing);
  });

  testWidgets('category chip filters the list', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          destinationsProvider.overrideWith((ref) async => _sample),
          destinationCategoryProvider
              .overrideWith((ref) => DestinationCategory.parks),
        ],
        child: const MaterialApp(home: DestinationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Yosemite'), findsWidgets);
    expect(find.text('Blue Ridge Parkway'), findsNothing);
  });

  testWidgets('shows a friendly error message when the connection fails',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          destinationsProvider.overrideWith(
            (ref) async => throw const AppException(
              'Cannot reach the destinations service. Please check your '
              'connection and try again.',
              type: AppExceptionType.network,
            ),
          ),
        ],
        child: const MaterialApp(home: DestinationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Cannot reach the destinations service'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });
}
