import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/gps/models/geofence.dart';
import 'package:explorer_os_mobile/features/gps/models/geofence_level.dart';
import 'package:explorer_os_mobile/features/gps/services/geofence_selector.dart';

void main() {
  const selector = GeofenceSelector();

  Geofence fence({
    required String id,
    required GeofenceLevel level,
    required double lat,
    required double lng,
    required double radius,
    int? priority,
    bool active = true,
  }) {
    return Geofence(
      id: id,
      locationId: 'location-$id',
      level: level,
      centerLat: lat,
      centerLng: lng,
      radiusMeters: radius,
      priorityOverride: priority,
      active: active,
    );
  }

  group('GeofenceSelector', () {
    test('returns null when no geofence contains the position', () {
      final result = selector.selectBest(
        geofences: [
          fence(
            id: 'county',
            level: GeofenceLevel.county,
            lat: 29.0,
            lng: -82.0,
            radius: 100,
          ),
        ],
        latitude: 29.1,
        longitude: -82.1,
      );

      expect(result, isNull);
    });

    test('ignores inactive geofences', () {
      final result = selector.selectBest(
        geofences: [
          fence(
            id: 'inactive-poi',
            level: GeofenceLevel.poi,
            lat: 29.0,
            lng: -82.0,
            radius: 1000,
            active: false,
          ),
          fence(
            id: 'county',
            level: GeofenceLevel.county,
            lat: 29.0,
            lng: -82.0,
            radius: 1000,
          ),
        ],
        latitude: 29.0,
        longitude: -82.0,
      );

      expect(result?.geofence.id, 'county');
    });

    test('city beats county', () {
      final result = selector.selectBest(
        geofences: [
          fence(
            id: 'county',
            level: GeofenceLevel.county,
            lat: 29.0,
            lng: -82.0,
            radius: 5000,
          ),
          fence(
            id: 'city',
            level: GeofenceLevel.city,
            lat: 29.0,
            lng: -82.0,
            radius: 3000,
          ),
        ],
        latitude: 29.0,
        longitude: -82.0,
      );

      expect(result?.geofence.id, 'city');
    });

    test('park beats city', () {
      final result = selector.selectBest(
        geofences: [
          fence(
            id: 'city',
            level: GeofenceLevel.city,
            lat: 29.0,
            lng: -82.0,
            radius: 5000,
          ),
          fence(
            id: 'park',
            level: GeofenceLevel.park,
            lat: 29.0,
            lng: -82.0,
            radius: 2000,
          ),
        ],
        latitude: 29.0,
        longitude: -82.0,
      );

      expect(result?.geofence.id, 'park');
    });

    test('POI beats park', () {
      final result = selector.selectBest(
        geofences: [
          fence(
            id: 'park',
            level: GeofenceLevel.park,
            lat: 29.0,
            lng: -82.0,
            radius: 2000,
          ),
          fence(
            id: 'poi',
            level: GeofenceLevel.poi,
            lat: 29.0,
            lng: -82.0,
            radius: 500,
          ),
        ],
        latitude: 29.0,
        longitude: -82.0,
      );

      expect(result?.geofence.id, 'poi');
    });

    test('museum beats park', () {
      final result = selector.selectBest(
        geofences: [
          fence(
            id: 'park',
            level: GeofenceLevel.park,
            lat: 29.0,
            lng: -82.0,
            radius: 3000,
          ),
          fence(
            id: 'museum',
            level: GeofenceLevel.museum,
            lat: 29.0,
            lng: -82.0,
            radius: 500,
          ),
        ],
        latitude: 29.0,
        longitude: -82.0,
      );

      expect(result?.geofence.id, 'museum');
    });

    test('when POI no longer contains position, park can become active', () {
      final geofences = [
        fence(
          id: 'park',
          level: GeofenceLevel.park,
          lat: 29.0,
          lng: -82.0,
          radius: 5000,
        ),
        fence(
          id: 'poi',
          level: GeofenceLevel.poi,
          lat: 29.0,
          lng: -82.0,
          radius: 100,
        ),
      ];

      final result = selector.selectBest(
        geofences: geofences,
        latitude: 29.0,
        longitude: -82.0,
      );

      expect(result?.geofence.id, 'poi');

      final resultAfterLeavingPoi = selector.selectBest(
        geofences: geofences,
        latitude: 29.0015,
        longitude: -82.0,
      );

      expect(resultAfterLeavingPoi?.geofence.id, 'park');
    });

    test('same-depth geofences use effective priority', () {
      final result = selector.selectBest(
        geofences: [
          fence(
            id: 'poi-low',
            level: GeofenceLevel.poi,
            lat: 29.0,
            lng: -82.0,
            radius: 1000,
            priority: 101,
          ),
          fence(
            id: 'poi-high',
            level: GeofenceLevel.poi,
            lat: 29.0,
            lng: -82.0,
            radius: 1000,
            priority: 999,
          ),
        ],
        latitude: 29.0,
        longitude: -82.0,
      );

      expect(result?.geofence.id, 'poi-high');
    });

    test('same depth and priority uses closest center', () {
      final result = selector.selectBest(
        geofences: [
          fence(
            id: 'far',
            level: GeofenceLevel.poi,
            lat: 29.001,
            lng: -82.0,
            radius: 1000,
            priority: 500,
          ),
          fence(
            id: 'near',
            level: GeofenceLevel.poi,
            lat: 29.0001,
            lng: -82.0,
            radius: 1000,
            priority: 500,
          ),
        ],
        latitude: 29.0,
        longitude: -82.0,
      );

      expect(result?.geofence.id, 'near');
    });

    test('distance is zero when position is at the geofence center', () {
      final result = selector.selectBest(
        geofences: [
          fence(
            id: 'center',
            level: GeofenceLevel.poi,
            lat: 29.0,
            lng: -82.0,
            radius: 100,
          ),
        ],
        latitude: 29.0,
        longitude: -82.0,
      );

      expect(result, isNotNull);
      expect(result!.distanceMeters, closeTo(0, 0.001));
    });
  });
}
