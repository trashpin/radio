import 'package:explorer_os_mobile/features/gps/gps_connection.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('health', () {
    test('accuracy → health bands', () {
      expect(healthForAccuracy(null), GpsHealth.none);
      expect(healthForAccuracy(5), GpsHealth.excellent);
      expect(healthForAccuracy(15), GpsHealth.good);
      expect(healthForAccuracy(40), GpsHealth.fair);
      expect(healthForAccuracy(200), GpsHealth.poor);
    });
    test('accuracy label in feet', () {
      expect(accuracyLabel(null), '—');
      expect(accuracyLabel(6), '20 feet'); // 6m ≈ 19.7ft
    });
  });

  group('deriveGpsConnection phases', () {
    test('unknown permission → checking', () {
      final s = deriveGpsConnection(const GpsStatus());
      expect(s.phase, GpsPhase.checkingPermission);
      expect(s.reliable, isFalse);
    });

    test('service disabled → gps off + needs action', () {
      final s = deriveGpsConnection(const GpsStatus(
          permission: LocationPermissionStatus.serviceDisabled));
      expect(s.phase, GpsPhase.gpsDisabled);
      expect(s.needsAction, isTrue);
    });

    test('denied / blocked', () {
      expect(
          deriveGpsConnection(const GpsStatus(
                  permission: LocationPermissionStatus.denied))
              .phase,
          GpsPhase.permissionDenied);
      expect(
          deriveGpsConnection(const GpsStatus(
                  permission: LocationPermissionStatus.deniedForever))
              .phase,
          GpsPhase.permissionBlocked);
    });

    test('granted, no fix → searching; times out after 20s', () {
      const g = GpsStatus(
          permission: LocationPermissionStatus.grantedWhenInUse,
          serviceEnabled: true,
          tracking: true);
      final s = deriveGpsConnection(g, searchingSeconds: 5);
      expect(s.phase, GpsPhase.searching);
      expect(s.timedOut, isFalse);
      final t = deriveGpsConnection(g, searchingSeconds: 25);
      expect(t.timedOut, isTrue);
      expect(t.message, contains('Still searching'));
    });

    test('fix without county → resolving county', () {
      final s = deriveGpsConnection(const GpsStatus(
        permission: LocationPermissionStatus.grantedWhenInUse,
        serviceEnabled: true,
        latitude: 29.2,
        longitude: -82.0,
        accuracyMeters: 12,
      ));
      expect(s.phase, GpsPhase.resolvingCounty);
      expect(s.health, GpsHealth.good);
      expect(s.reliable, isTrue);
    });

    test('fix + county → ready', () {
      final s = deriveGpsConnection(
        const GpsStatus(
          permission: LocationPermissionStatus.grantedWhenInUse,
          serviceEnabled: true,
          latitude: 29.2,
          longitude: -82.0,
          accuracyMeters: 6,
        ),
        county: 'Marion',
      );
      expect(s.phase, GpsPhase.ready);
      expect(s.reliable, isTrue);
      expect(s.health, GpsHealth.excellent);
      expect(s.steps.last.label, contains('Explorer Mode ready'));
    });

    test('poor accuracy fix is not reliable', () {
      final s = deriveGpsConnection(
        const GpsStatus(
          permission: LocationPermissionStatus.grantedWhenInUse,
          serviceEnabled: true,
          latitude: 1,
          longitude: 1,
          accuracyMeters: 300,
        ),
        county: 'Marion',
      );
      expect(s.health, GpsHealth.poor);
      expect(s.reliable, isFalse);
    });
  });
}
