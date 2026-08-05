import 'package:explorer_os_mobile/features/admin/location_tester/location_tester_page.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final locations = <MasterLocation>[
    MasterLocation(
      id: 'near',
      name: 'Near Park',
      type: LocationType.cityPark,
      latitude: 29.1872,
      longitude: -82.1401,
      contentStatus: ContentStatus.published,
      audioFiles: const ['https://x/a.mp3'],
    ),
    MasterLocation(
      id: 'draft',
      name: 'Draft Diner',
      type: LocationType.restaurant,
      latitude: 29.190,
      longitude: -82.135,
      contentStatus: ContentStatus.draft,
    ),
    MasterLocation(
      id: 'far',
      name: 'Far Attraction',
      type: LocationType.attraction,
      latitude: 30.324, // ~80 mi away
      longitude: -81.655,
      contentStatus: ContentStatus.published,
      audioFiles: const ['https://x/b.mp3'],
    ),
  ];

  testWidgets('Location Tester returns near + rejects draft/out-of-range',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        masterLocationsProvider.overrideWith((ref) async => locations),
      ],
      child: const MaterialApp(home: Scaffold(body: LocationTesterPage())),
    ));
    await tester.pumpAndSettle();

    // Fields are prefilled with the audited coordinate; run the test.
    await tester.tap(find.text('Run test'));
    await tester.pumpAndSettle();

    // Summary reflects the returned count.
    expect(find.textContaining('returned to the user'), findsOneWidget);
    // Nearest is the published near park.
    expect(find.textContaining('Near Park'), findsWidgets);
    // The draft is rejected with the publish reason.
    expect(find.textContaining('draft/archived'), findsOneWidget);
    // The far one is rejected as out of range.
    expect(find.textContaining('out of range'), findsOneWidget);
  });
}
