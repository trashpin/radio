// Widget tests for the Destinations screen.
//
// These tests override `destinationsProvider` so we can deterministically drive
// each UI state (list, empty, error) WITHOUT a live Supabase connection. This
// proves the screen renders correctly for every backend outcome.

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/destinations_screen.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows destinations returned by the backend', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          destinationsProvider.overrideWith((ref) async => const [
                Destination(id: '1', name: 'Yosemite'),
                Destination(id: '2', name: 'Everglades'),
              ]),
        ],
        child: const MaterialApp(home: DestinationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Yosemite'), findsOneWidget);
    expect(find.text('Everglades'), findsOneWidget);
    expect(find.text('No destinations found.'), findsNothing);
  });

  testWidgets('shows "No destinations found." when the table is empty',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          destinationsProvider
              .overrideWith((ref) async => const <Destination>[]),
        ],
        child: const MaterialApp(home: DestinationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No destinations found.'), findsOneWidget);
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
