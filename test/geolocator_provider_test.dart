// Unit test for the geolocator adapter's pure mapping. The permission/stream
// paths require a device, but the Position -> GPSLocation mapping is pure and
// verified here.

import 'package:explorer_os_mobile/features/gps/models/gps_enums.dart';
import 'package:explorer_os_mobile/features/gps/services/geolocator_location_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toGpsLocation maps every field from a geolocator Position', () {
    final ts = DateTime(2026, 7, 24, 14);
    final position = Position(
      latitude: 40.5,
      longitude: -111.9,
      timestamp: ts,
      accuracy: 5,
      altitude: 1500,
      altitudeAccuracy: 3,
      heading: 90,
      headingAccuracy: 2,
      speed: 12.5,
      speedAccuracy: 1,
    );

    final loc = GeolocatorLocationProvider.toGpsLocation(position);

    expect(loc.latitude, 40.5);
    expect(loc.longitude, -111.9);
    expect(loc.timestamp, ts);
    expect(loc.accuracyMeters, 5);
    expect(loc.elevationMeters, 1500);
    expect(loc.headingDegrees, 90);
    expect(loc.speedMps, 12.5);
  });

  test('provider reports the system provider type', () {
    expect(GeolocatorLocationProvider().type, GpsProviderType.system);
  });
}
