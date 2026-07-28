import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/gps/models/gps_location.dart';
import 'package:explorer_os_mobile/features/gps/models/gps_status.dart';
import 'package:explorer_os_mobile/features/gps/services/gps_logger.dart';

void main() {
  group('LocationPermissionStatus', () {
    test('isGranted only for when-in-use / always', () {
      expect(LocationPermissionStatus.grantedWhenInUse.isGranted, isTrue);
      expect(LocationPermissionStatus.grantedAlways.isGranted, isTrue);
      expect(LocationPermissionStatus.denied.isGranted, isFalse);
      expect(LocationPermissionStatus.deniedForever.isGranted, isFalse);
      expect(LocationPermissionStatus.serviceDisabled.isGranted, isFalse);
      expect(LocationPermissionStatus.unknown.isGranted, isFalse);
    });

    test('every status has a non-empty user message', () {
      for (final s in LocationPermissionStatus.values) {
        expect(s.message, isNotEmpty);
      }
    });
  });

  group('GpsStatus', () {
    test('initial has no fix and is not granted/tracking', () {
      final s = GpsStatus.initial();
      expect(s.hasFix, isFalse);
      expect(s.isGranted, isFalse);
      expect(s.tracking, isFalse);
      expect(s.updateCount, 0);
    });

    test('copyWith updates fields and reports a fix', () {
      final s = GpsStatus.initial().copyWith(
        permission: LocationPermissionStatus.grantedWhenInUse,
        latitude: 29.18,
        longitude: -81.71,
        speedMps: 10,
        updateCount: 3,
        tracking: true,
      );
      expect(s.hasFix, isTrue);
      expect(s.isGranted, isTrue);
      expect(s.speedMph, closeTo(22.37, 0.1));
      expect(s.updateCount, 3);
    });
  });

  group('GpsLogger', () {
    test('counts only location updates and keeps a bounded buffer', () {
      final log = GpsLogger(capacity: 5);
      log.permissionRequested();
      log.permissionGranted('whenInUse');
      expect(log.updateCount, 0);

      for (var i = 0; i < 3; i++) {
        log.locationUpdated(GPSLocation(
          latitude: 29 + i * 0.001,
          longitude: -81,
          timestamp: DateTime(2026, 1, 1, 12, 0, i),
          accuracyMeters: 5,
        ));
      }
      expect(log.updateCount, 3);
      // capacity 5 → only the most recent 5 entries retained.
      expect(log.entries.length, 5);
      expect(log.lastEntry!.kind, GpsLogKind.locationUpdated);
    });

    test('clear resets entries and counters', () {
      final log = GpsLogger();
      log.gpsLost('timeout');
      log.gpsRestored();
      log.clear();
      expect(log.entries, isEmpty);
      expect(log.updateCount, 0);
    });
  });
}
