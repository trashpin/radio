import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/discover_area/controllers/area_tour_controller.dart';
import 'package:explorer_os_mobile/features/discover_area/models/nearby_attractions.dart';
import 'package:explorer_os_mobile/features/discover_area/models/tour_mode.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

AttractionMatch _stop(String id) => AttractionMatch(
      location: MasterLocation.fromJson({
        'id': id,
        'name': id,
        'category': 'museum',
        'latitude': 29.2,
        'longitude': -82.0,
      }),
      distanceMeters: 100,
    );

void main() {
  group('TourMode', () {
    test('walking has a tighter trigger radius than driving', () {
      expect(
        TourMode.walking.triggerRadiusMeters < TourMode.driving.triggerRadiusMeters,
        isTrue,
      );
    });

    test('walking searches a smaller area for candidate stops than driving',
        () {
      expect(
        TourMode.walking.stopSearchRadiusMeters <
            TourMode.driving.stopSearchRadiusMeters,
        isTrue,
      );
    });
  });

  group('AreaTourState', () {
    test('starts with no stops visited', () {
      final state = AreaTourState(stops: [_stop('a'), _stop('b')]);
      expect(state.visitedCount, 0);
      expect(state.isVisited(_stop('a')), isFalse);
    });

    test('isVisited reflects visitedIds by location id', () {
      final a = _stop('a');
      final state = AreaTourState(stops: [a, _stop('b')], visitedIds: {'a'});
      expect(state.isVisited(a), isTrue);
      expect(state.visitedCount, 1);
    });

    test('copyWith preserves stops and only changes what is passed', () {
      final state = AreaTourState(stops: [_stop('a')], running: true);
      final next = state.copyWith(visitedIds: {'a'});
      expect(next.stops, state.stops);
      expect(next.running, isTrue); // unchanged
      expect(next.visitedIds, {'a'});
    });
  });
}
