import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/gps/models/geofence.dart';
import 'package:explorer_os_mobile/features/gps/models/geofence_level.dart';
import 'package:explorer_os_mobile/features/gps/services/geofence_intelligence_service.dart';

void main() {
  late GeofenceIntelligenceService intelligence;

  setUp(() {
    intelligence = GeofenceIntelligenceService();
  });

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

  test('selects the deepest matching geofence', () {
    final result = intelligence.evaluate(
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
          radius: 4000,
        ),
        fence(
          id: 'park',
          level: GeofenceLevel.park,
          lat: 29.0,
          lng: -82.0,
          radius: 3000,
        ),
        fence(
          id: 'poi',
          level: GeofenceLevel.poi,
          lat: 29.0,
          lng: -82.0,
          radius: 1000,
        ),
      ],
      latitude: 29.0,
      longitude: -82.0,
    );

    expect(result, isNotNull);
    expect(result!.geofence.id, 'poi');
    expect(result.geofence.level, GeofenceLevel.poi);
  });

  test('returns null when no geofence contains the position', () {
    final result = intelligence.evaluate(
      geofences: [
        fence(
          id: 'park',
          level: GeofenceLevel.park,
          lat: 29.0,
          lng: -82.0,
          radius: 100,
        ),
      ],
      latitude: 29.1,
      longitude: -82.1,
    );

    expect(result, isNull);
    expect(intelligence.current, isNull);
  });

  test('ignores inactive geofences', () {
    final result = intelligence.evaluate(
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
          id: 'park',
          level: GeofenceLevel.park,
          lat: 29.0,
          lng: -82.0,
          radius: 1000,
        ),
      ],
      latitude: 29.0,
      longitude: -82.0,
    );

    expect(result?.geofence.id, 'park');
  });

  test('updates current match when position changes', () {
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

    final first = intelligence.evaluate(
      geofences: geofences,
      latitude: 29.0,
      longitude: -82.0,
    );

    expect(first?.geofence.id, 'poi');
    expect(intelligence.current?.geofence.id, 'poi');

    final second = intelligence.evaluate(
      geofences: geofences,
      latitude: 29.0015,
      longitude: -82.0,
    );

    expect(second?.geofence.id, 'park');
    expect(intelligence.current?.geofence.id, 'park');
  });

  test('reset clears the current match', () {
    intelligence.evaluate(
      geofences: [
        fence(
          id: 'park',
          level: GeofenceLevel.park,
          lat: 29.0,
          lng: -82.0,
          radius: 1000,
        ),
      ],
      latitude: 29.0,
      longitude: -82.0,
    );

    expect(intelligence.current, isNotNull);

    intelligence.reset();

    expect(intelligence.current, isNull);
  });
}
