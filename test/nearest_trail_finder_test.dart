import 'package:explorer_os_mobile/features/ocala_forest/discover/services/nearest_trail_finder.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:flutter_test/flutter_test.dart';

ForestTrail _trail(String id, List<ForestTrailPoint> vertices) => ForestTrail(
      id: id,
      forestId: 'f1',
      trailNo: id,
      parts: [vertices],
    );

void main() {
  group('nearestTrailId', () {
    test('finds the trail whose geometry passes closest to the fix', () {
      final near = _trail('near', [(lat: 29.0, lng: -81.6), (lat: 29.001, lng: -81.6)]);
      final far = _trail('far', [(lat: 30.0, lng: -82.0), (lat: 30.001, lng: -82.0)]);

      final result = nearestTrailId(29.0, -81.6, [near, far]);
      expect(result, 'near');
    });

    test('returns null when nothing is within maxMeters', () {
      final far = _trail('far', [(lat: 30.0, lng: -82.0)]);
      final result = nearestTrailId(29.0, -81.6, [far], maxMeters: 100);
      expect(result, isNull);
    });

    test('returns null for an empty trail list', () {
      expect(nearestTrailId(29.0, -81.6, const []), isNull);
    });

    test('a trail with multiple parts is still matched by its closest vertex', () {
      final multiPart = ForestTrail(
        id: 'multi',
        forestId: 'f1',
        trailNo: 'multi',
        parts: [
          [(lat: 40.0, lng: -90.0)], // far part
          [(lat: 29.0001, lng: -81.6001)], // close part
        ],
      );
      final result = nearestTrailId(29.0, -81.6, [multiPart], maxMeters: 50);
      expect(result, 'multi');
    });
  });
}
