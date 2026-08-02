import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/discover_area/models/nearby_attractions.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

MasterLocation _loc({
  required String id,
  required String category,
  double lat = 29.2,
  double lng = -82.0,
  bool active = true,
  bool hidden = false,
}) =>
    MasterLocation.fromJson({
      'id': id,
      'name': id,
      'category': category,
      'latitude': lat,
      'longitude': lng,
      'active': active,
      'hidden': hidden,
    });

void main() {
  group('nearbyAttractions', () {
    final area = _loc(id: 'area-1', category: 'area', lat: 29.2, lng: -82.0);

    test('includes attraction-type locations within radius, sorted by '
        'distance', () {
      final near = _loc(id: 'museum-near', category: 'museum', lat: 29.201, lng: -82.0);
      final far = _loc(id: 'museum-far', category: 'museum', lat: 29.25, lng: -82.0);
      final result = nearbyAttractions([near, far], area, radiusMeters: 3000);
      expect(result.map((m) => m.location.id), ['museum-near']);
    });

    test('excludes the area itself even if it matches an attraction type',
        () {
      final selfAsAttraction = _loc(id: 'area-1', category: 'museum');
      final result = nearbyAttractions([selfAsAttraction], area);
      expect(result, isEmpty);
    });

    test('excludes non-attraction types', () {
      final restaurant = _loc(id: 'r1', category: 'restaurant');
      final gasStation = _loc(id: 'g1', category: 'gas_station');
      final result = nearbyAttractions([restaurant, gasStation], area);
      expect(result, isEmpty);
    });

    test('includes every spec attraction type', () {
      final all = [
        _loc(id: '1', category: 'museum'),
        _loc(id: '2', category: 'state_park'),
        _loc(id: '3', category: 'national_park'),
        _loc(id: '4', category: 'county_park'),
        _loc(id: '5', category: 'historic_site'),
        _loc(id: '6', category: 'historic_district'),
        _loc(id: '7', category: 'trail'),
        _loc(id: '8', category: 'trailhead'),
        _loc(id: '9', category: 'scenic_overlook'),
        _loc(id: '10', category: 'hidden_gem'),
      ];
      final result = nearbyAttractions(all, area);
      expect(result, hasLength(10));
    });

    test('excludes inactive or hidden attractions', () {
      final inactive = _loc(id: '1', category: 'museum', active: false);
      final hidden = _loc(id: '2', category: 'museum', hidden: true);
      final result = nearbyAttractions([inactive, hidden], area);
      expect(result, isEmpty);
    });

    test('respects the limit parameter', () {
      final many = List.generate(
        50,
        (i) => _loc(id: 'm$i', category: 'museum', lat: 29.2 + i * 0.0001),
      );
      final result = nearbyAttractions(many, area, limit: 5);
      expect(result, hasLength(5));
    });

    test('returns empty when the area itself has no coordinates', () {
      final areaNoCoords = MasterLocation.fromJson({
        'id': 'area-2',
        'name': 'area-2',
        'category': 'area',
      });
      final museum = _loc(id: '1', category: 'museum');
      final result = nearbyAttractions([museum], areaNoCoords);
      expect(result, isEmpty);
    });
  });
}
