import 'package:explorer_os_mobile/features/discover_area/presentation/marion_discovery_screen.dart';
import 'package:explorer_os_mobile/features/discover_area/presentation/marion_nature_screen.dart';
import 'package:explorer_os_mobile/features/discovery/data/species_repository.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _marion = MasterLocation(
  id: 'm',
  name: 'Marion County',
  type: LocationType.county,
  latitude: 29.2,
  longitude: -82.1,
  county: 'Marion',
  active: true,
  shortDescription: 'Discover the rich history of Marion County.',
  narrationScript: 'Welcome to Marion County, named for the Swamp Fox…',
  images: const ['https://x/marion.jpg'],
);

final _spring = MasterLocation(
  id: 's1',
  name: 'Silver Springs',
  type: LocationType.spring,
  latitude: 29.21,
  longitude: -82.05,
  county: 'Marion',
  active: true,
  description: 'A famous Marion County spring.',
);

final _statePark = MasterLocation(
  id: 'sp1',
  name: 'Silver Springs State Park',
  type: LocationType.statePark,
  latitude: 29.21,
  longitude: -82.05,
  active: true,
  description: 'A Florida state park in Marion County.',
);

Widget _wrap(Widget child, {List<MasterLocation> locations = const []}) =>
    ProviderScope(
      overrides: [
        masterLocationsProvider.overrideWith((ref) async => locations),
        speciesByCategoryProvider.overrideWith((ref, category) async =>
            category == 'animals'
                ? [
                    const Species(
                        id: 'b',
                        category: 'animals',
                        commonName: 'Florida Black Bear',
                        description: 'The largest land mammal in Florida.')
                  ]
                : const <Species>[]),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  testWidgets('Marion discovery shows History + Nature with the history blurb',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        _wrap(const MarionDiscoveryScreen(), locations: [_marion]));
    await tester.pumpAndSettle();

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Nature'), findsOneWidget);
    expect(find.textContaining('Discover the rich history'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Explore'), findsOneWidget);
  });

  testWidgets('Nature screen renders species + location sections (non-empty)',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_wrap(const MarionNatureScreen(),
        locations: [_spring, _statePark]));
    await tester.pumpAndSettle();

    // Species section with data shows; empty ones are hidden.
    expect(find.text('Wildlife'), findsOneWidget);
    expect(find.text('Florida Black Bear'), findsOneWidget);
    expect(find.text('Mammals'), findsNothing); // no data → hidden
    // Location sections.
    expect(find.text('Springs'), findsOneWidget);
    expect(find.text('Silver Springs'), findsOneWidget);
    expect(find.text('State Parks'), findsOneWidget);
    expect(find.text('Silver Springs State Park'), findsOneWidget);
  });
}
