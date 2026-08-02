import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/maps/services/driving_distance_service.dart';

void main() {
  group('parseDistanceMatrix', () {
    test('parses a healthy single-row response', () {
      final json = {
        'status': 'OK',
        'rows': [
          {
            'elements': [
              {
                'status': 'OK',
                'distance': {'value': 12874, 'text': '8.0 mi'},
                'duration': {'value': 900, 'text': '15 mins'},
              },
              {
                'status': 'OK',
                'distance': {'value': 4000, 'text': '2.5 mi'},
                'duration': {'value': 400, 'text': '7 mins'},
              },
            ],
          },
        ],
      };

      final out = parseDistanceMatrix(json, ['damDiner', 'otherGem']);
      expect(out['damDiner']!.distanceMeters, 12874);
      expect(out['damDiner']!.durationSeconds, 900);
      expect(out['otherGem']!.distanceMeters, 4000);
    });

    test('top-level non-OK status yields nothing (fall back to straight-line)',
        () {
      final out = parseDistanceMatrix({
        'status': 'REQUEST_DENIED',
        'error_message': 'This API project is not authorized...',
      }, [
        'gem1',
      ]);
      expect(out, isEmpty);
    });

    test('per-element non-OK status is skipped, others still parse', () {
      final json = {
        'status': 'OK',
        'rows': [
          {
            'elements': [
              {'status': 'NOT_FOUND'},
              {
                'status': 'OK',
                'distance': {'value': 1000},
                'duration': {'value': 120},
              },
            ],
          },
        ],
      };
      final out = parseDistanceMatrix(json, ['badGem', 'goodGem']);
      expect(out.containsKey('badGem'), isFalse);
      expect(out['goodGem']!.distanceMeters, 1000);
    });

    test('missing rows/elements returns empty rather than throwing', () {
      expect(parseDistanceMatrix({'status': 'OK'}, ['a']), isEmpty);
      expect(
        parseDistanceMatrix({
          'status': 'OK',
          'rows': [
            {},
          ],
        }, [
          'a',
        ]),
        isEmpty,
      );
    });
  });

  group('DrivingDistanceService.batchDrivingDistances', () {
    test('returns empty map (never throws) with no API key configured', () async {
      final service = DrivingDistanceService();
      final out = await service.batchDrivingDistances(
        originLat: 29.04,
        originLng: -81.93,
        destinations: {
          'damDiner': (lat: 29.0119, lng: -81.9177),
        },
      );
      // No GOOGLE_MAPS_API_KEY in the test environment -> fails closed.
      expect(out, isEmpty);
    });

    test('empty destinations short-circuits without a network call', () async {
      final service = DrivingDistanceService(
        getFn: (_) async => throw StateError('should not be called'),
      );
      final out = await service.batchDrivingDistances(
        originLat: 29.04,
        originLng: -81.93,
        destinations: const {},
      );
      expect(out, isEmpty);
    });
  });
}
