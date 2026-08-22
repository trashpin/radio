// Unit tests for the Ocala Forest Explorer's GPS-arrival detection — pure
// logic (ForestExperienceEngine wraps the existing, generic
// LocationTriggerEngine), no Riverpod/audio/I-O, mirroring this session's
// established TripTracker-style plain-class testing approach.

import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_experience_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:flutter_test/flutter_test.dart';

ForestLocation _loc(
  String id, {
  double lat = 29.0,
  double lng = -81.6,
  double? geofenceRadiusMeters,
  bool active = true,
  String triggerType = 'geofence',
}) =>
    ForestLocation(
      id: id,
      forestId: 'forest-1',
      name: 'Location $id',
      category: 'Spring',
      latitude: lat,
      longitude: lng,
      geofenceRadiusMeters: geofenceRadiusMeters,
      active: active,
      triggerType: triggerType,
    );

GPSLocation _fix(double lat, double lng) =>
    GPSLocation(latitude: lat, longitude: lng, timestamp: DateTime(2026, 1, 1));

void main() {
  group('ForestExperienceEngine', () {
    test('fires an arrival when the fix is within the location\'s geofence radius', () {
      final engine = ForestExperienceEngine();
      final loc = _loc('a', lat: 29.0, lng: -81.6, geofenceRadiusMeters: 100);
      final arrivals = engine.onLocation(_fix(29.0, -81.6), [loc]);
      expect(arrivals, hasLength(1));
      expect(arrivals.first.location.id, 'a');
    });

    test('does not fire when the fix is outside the geofence radius', () {
      final engine = ForestExperienceEngine();
      final loc = _loc('a', lat: 29.0, lng: -81.6, geofenceRadiusMeters: 50);
      // ~1.1km away at this latitude.
      final arrivals = engine.onLocation(_fix(29.01, -81.6), [loc]);
      expect(arrivals, isEmpty);
    });

    test('falls back to the default 150m radius when none is set', () {
      final engine = ForestExperienceEngine();
      final loc = _loc('a', lat: 29.0, lng: -81.6); // no geofenceRadiusMeters
      final arrivals = engine.onLocation(_fix(29.0, -81.6), [loc]);
      expect(arrivals, hasLength(1));
    });

    test('only fires once per continuous stay, then again after leaving and returning', () {
      final engine = ForestExperienceEngine();
      final loc = _loc('a', lat: 29.0, lng: -81.6, geofenceRadiusMeters: 100);

      expect(engine.onLocation(_fix(29.0, -81.6), [loc]), hasLength(1));
      // Still inside — no repeat.
      expect(engine.onLocation(_fix(29.0, -81.6), [loc]), isEmpty);
      // Leaves.
      expect(engine.onLocation(_fix(29.05, -81.6), [loc]), isEmpty);
      // Returns — fires again.
      expect(engine.onLocation(_fix(29.0, -81.6), [loc]), hasLength(1));
    });

    test('ignores inactive locations', () {
      final engine = ForestExperienceEngine();
      final loc = _loc('a', lat: 29.0, lng: -81.6, active: false);
      expect(engine.onLocation(_fix(29.0, -81.6), [loc]), isEmpty);
    });

    test('ignores locations with a non-geofence trigger type', () {
      final engine = ForestExperienceEngine();
      final loc = _loc('a', lat: 29.0, lng: -81.6, triggerType: 'qr_code');
      expect(engine.onLocation(_fix(29.0, -81.6), [loc]), isEmpty);
    });

    test('can fire for multiple locations reached in the same fix', () {
      final engine = ForestExperienceEngine();
      final a = _loc('a', lat: 29.0, lng: -81.6, geofenceRadiusMeters: 5000);
      final b = _loc('b', lat: 29.001, lng: -81.601, geofenceRadiusMeters: 5000);
      final arrivals = engine.onLocation(_fix(29.0, -81.6), [a, b]);
      expect(arrivals.map((e) => e.location.id).toSet(), {'a', 'b'});
    });
  });
}
