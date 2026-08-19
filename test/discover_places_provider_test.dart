import 'package:explorer_os_mobile/features/discover_area/providers/discover_places_provider.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter_test/flutter_test.dart';

MasterLocation _loc(
  String id,
  LocationType type, {
  double lat = 29.2,
  double lng = -82.0,
  String? county = 'Marion',
  bool active = true,
  bool hidden = false,
}) =>
    MasterLocation(
      id: id,
      name: id,
      type: type,
      latitude: lat,
      longitude: lng,
      county: county,
      active: active,
      hidden: hidden,
    );

void main() {
  group('isMarionOrUnset', () {
    test('accepts Marion (any case/whitespace)', () {
      expect(isMarionOrUnset('Marion'), isTrue);
      expect(isMarionOrUnset(' marion '), isTrue);
      expect(isMarionOrUnset('MARION'), isTrue);
    });

    test('accepts null/blank (sparse data is kept, not dropped)', () {
      expect(isMarionOrUnset(null), isTrue);
      expect(isMarionOrUnset(''), isTrue);
      expect(isMarionOrUnset('   '), isTrue);
    });

    test('rejects a different county', () {
      expect(isMarionOrUnset('Alachua'), isFalse);
    });
  });

  group('discoverLocationsOfTypes', () {
    test('is county-wide: a far-away same-type match is included, not '
        'eliminated by distance', () {
      // ~0.6mi from origin.
      final near = _loc('near', LocationType.spring, lat: 29.208, lng: -82.0);
      // ~30mi from origin -- well past every other radius cap in the app.
      final far = _loc('far', LocationType.spring, lat: 29.63, lng: -82.0);
      final result = discoverLocationsOfTypes(
        [near, far],
        {LocationType.spring},
        lat: 29.2,
        lng: -82.0,
      );
      expect(result.map((n) => n.location.id), ['near', 'far']);
    });

    test('sorts nearest-first', () {
      final a = _loc('a', LocationType.museum, lat: 29.25, lng: -82.0);
      final b = _loc('b', LocationType.museum, lat: 29.201, lng: -82.0);
      final c = _loc('c', LocationType.museum, lat: 29.22, lng: -82.0);
      final result = discoverLocationsOfTypes(
        [a, b, c],
        {LocationType.museum},
        lat: 29.2,
        lng: -82.0,
      );
      expect(result.map((n) => n.location.id), ['b', 'c', 'a']);
    });

    test('excludes types outside the requested set', () {
      final park = _loc('park', LocationType.cityPark);
      final spring = _loc('spring', LocationType.spring);
      final result = discoverLocationsOfTypes(
        [park, spring],
        {LocationType.cityPark, LocationType.countyPark},
        lat: 29.2,
        lng: -82.0,
      );
      expect(result.map((n) => n.location.id), ['park']);
    });

    test('excludes inactive, hidden, and other-county locations', () {
      final inactive = _loc('inactive', LocationType.spring, active: false);
      final hidden = _loc('hidden', LocationType.spring, hidden: true);
      final otherCounty =
          _loc('other', LocationType.spring, county: 'Alachua');
      final blankCounty = _loc('blank', LocationType.spring, county: null);
      final result = discoverLocationsOfTypes(
        [inactive, hidden, otherCounty, blankCounty],
        {LocationType.spring},
        lat: 29.2,
        lng: -82.0,
      );
      expect(result.map((n) => n.location.id), ['blank']);
    });

    test('LOCAL PARKS vs STATE PARKS type sets stay disjoint', () {
      expect(discoverLocalParkTypes, {
        LocationType.countyPark,
        LocationType.cityPark,
      });
      expect(discoverStateParkTypes, {
        LocationType.statePark,
        LocationType.nationalPark,
      });
      expect(
        discoverLocalParkTypes.intersection(discoverStateParkTypes),
        isEmpty,
      );
    });

    test('MUSEUMS & HISTORICAL POINTS covers museum/historic/attraction '
        'types', () {
      expect(discoverMuseumHistoricTypes, {
        LocationType.museum,
        LocationType.historicSite,
        LocationType.historicDistrict,
        LocationType.attraction,
        LocationType.pointOfInterest,
        LocationType.scenicOverlook,
        LocationType.hiddenGem,
      });
    });
  });
}
