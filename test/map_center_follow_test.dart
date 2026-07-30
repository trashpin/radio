import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/features/gps/controllers/gps_controller.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/travel_context.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';

/// A drivable stand-in for the real GPS controller so we can push fixes.
class _FakeGpsController extends GpsController {
  @override
  TravelContext build() => TravelContext.initial();

  void push(double lat, double lng) {
    state = TravelContext(
      timestamp: DateTime.now(),
      location: GPSLocation(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
      ),
    );
  }
}

void main() {
  ProviderContainer makeContainer(_FakeGpsController fake) => ProviderContainer(
        overrides: [
          gpsControllerProvider.overrideWith(() => fake),
        ],
      );

  test('mapCenter auto-follows the live GPS fix', () {
    final fake = _FakeGpsController();
    final c = makeContainer(fake);
    addTearDown(c.dispose);

    expect(c.read(mapCenterProvider), isNull);
    c.read(gpsControllerProvider.notifier) as _FakeGpsController;
    fake.push(29.18, -82.14); // Marion County, FL

    final center = c.read(mapCenterProvider);
    expect(center, isNotNull);
    expect(center!.latitude, closeTo(29.18, 1e-6));
    expect(center.longitude, closeTo(-82.14, 1e-6));
  });

  test('a manual pan pauses GPS follow, then a fresh fix is ignored briefly',
      () {
    final fake = _FakeGpsController();
    final c = makeContainer(fake);
    addTearDown(c.dispose);

    c.read(mapCenterProvider); // instantiate + wire the listener
    c.read(mapCenterProvider.notifier).set(const LatLng(28.0, -81.0));
    expect(c.read(mapCenterProvider), const LatLng(28.0, -81.0));

    // A new GPS fix within the manual-hold window must NOT override the pan.
    fake.push(29.18, -82.14);
    expect(c.read(mapCenterProvider), const LatLng(28.0, -81.0));
  });

  test('follow() resumes GPS tracking after a manual pan', () {
    final fake = _FakeGpsController();
    final c = makeContainer(fake);
    addTearDown(c.dispose);

    c.read(mapCenterProvider);
    c.read(mapCenterProvider.notifier).set(const LatLng(28.0, -81.0));
    c.read(mapCenterProvider.notifier).follow(const LatLng(28.0, -81.0));

    fake.push(29.18, -82.14);
    expect(c.read(mapCenterProvider)!.latitude, closeTo(29.18, 1e-6));
  });

  test('seed() only fills an empty center and never blocks GPS', () {
    final fake = _FakeGpsController();
    final c = makeContainer(fake);
    addTearDown(c.dispose);

    c.read(mapCenterProvider);
    c.read(mapCenterProvider.notifier).seed(const LatLng(27.9, -82.4));
    expect(c.read(mapCenterProvider), const LatLng(27.9, -82.4));

    // GPS still takes over the seeded default.
    fake.push(29.18, -82.14);
    expect(c.read(mapCenterProvider)!.latitude, closeTo(29.18, 1e-6));
  });
}
