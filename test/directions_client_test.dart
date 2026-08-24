import 'package:explorer_os_mobile/features/navigation/services/directions_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodePolyline', () {
    test('decodes Google\'s own canonical documented example', () {
      // https://developers.google.com/maps/documentation/utilities/polylinealgorithm
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points.length, 3);
      expect(points[0].lat, closeTo(38.5, 0.00001));
      expect(points[0].lng, closeTo(-120.2, 0.00001));
      expect(points[1].lat, closeTo(40.7, 0.00001));
      expect(points[1].lng, closeTo(-120.95, 0.00001));
      expect(points[2].lat, closeTo(43.252, 0.00001));
      expect(points[2].lng, closeTo(-126.453, 0.00001));
    });

    test('an empty string decodes to no points', () {
      expect(decodePolyline(''), isEmpty);
    });
  });

  group('parseDirectionsResponse — overview polyline + duration', () {
    test('parses the overview_polyline and leg duration when present', () {
      final json = {
        'status': 'OK',
        'routes': [
          {
            'overview_polyline': {'points': '_p~iF~ps|U_ulLnnqC_mqNvxq`@'},
            'legs': [
              {
                'distance': {'value': 12000},
                'duration': {'value': 900},
                'steps': [
                  {
                    'html_instructions': 'Head north',
                    'maneuver': 'depart',
                    'distance': {'value': 12000},
                    'start_location': {'lat': 38.5, 'lng': -120.2},
                    'end_location': {'lat': 43.252, 'lng': -126.453},
                  },
                ],
              },
            ],
          },
        ],
      };
      final plan = parseDirectionsResponse(json);
      expect(plan, isNotNull);
      expect(plan!.totalDurationSeconds, 900);
      expect(plan.overviewPolyline.length, 3);
    });

    test('overviewPolyline is empty (not an error) when Google omits it', () {
      final json = {
        'status': 'OK',
        'routes': [
          {
            'legs': [
              {
                'distance': {'value': 500},
                'steps': [
                  {
                    'html_instructions': 'Head north',
                    'maneuver': 'depart',
                    'distance': {'value': 500},
                    'start_location': {'lat': 1.0, 'lng': 2.0},
                    'end_location': {'lat': 1.001, 'lng': 2.001},
                  },
                ],
              },
            ],
          },
        ],
      };
      final plan = parseDirectionsResponse(json);
      expect(plan, isNotNull);
      expect(plan!.overviewPolyline, isEmpty);
      expect(plan.totalDurationSeconds, isNull);
    });
  });
}
