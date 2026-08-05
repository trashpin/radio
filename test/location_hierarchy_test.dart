import 'package:explorer_os_mobile/features/locations/location_hierarchy.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter_test/flutter_test.dart';

MasterLocation _l(String id, LocationType t, {String? parent}) => MasterLocation(
      id: id,
      name: id,
      type: t,
      parentLocationId: parent,
    );

void main() {
  // Country → State → County → City → Park → POI
  final country = _l('us', LocationType.country);
  final state = _l('fl', LocationType.state, parent: 'us');
  final county = _l('marion', LocationType.county, parent: 'fl');
  final city = _l('ocala', LocationType.city, parent: 'marion');
  final park = _l('tuscawilla', LocationType.cityPark, parent: 'ocala');
  final poi = _l('fountain', LocationType.pointOfInterest, parent: 'tuscawilla');
  final all = [country, state, county, city, park, poi];
  final byId = LocationHierarchy.indexById(all);

  test('ancestorsOf walks up to the root, nearest first', () {
    final anc = LocationHierarchy.ancestorsOf(poi, byId).map((e) => e.id);
    expect(anc.toList(), ['tuscawilla', 'ocala', 'marion', 'fl', 'us']);
  });

  test('chainTo is breadcrumb order root→leaf', () {
    final chain = LocationHierarchy.chainTo(poi, byId).map((e) => e.id);
    expect(chain.toList(), ['us', 'fl', 'marion', 'ocala', 'tuscawilla', 'fountain']);
  });

  test('nearestOfType finds the enclosing county/city', () {
    expect(LocationHierarchy.nearestOfType(poi, LocationType.county, byId)?.id,
        'marion');
    expect(LocationHierarchy.nearestOfType(poi, LocationType.city, byId)?.id,
        'ocala');
    expect(LocationHierarchy.nearestOfType(poi, LocationType.village, byId),
        isNull);
  });

  test('childrenOf and descendantsOf', () {
    expect(LocationHierarchy.childrenOf('marion', all).map((e) => e.id),
        ['ocala']);
    expect(
        LocationHierarchy.descendantsOf('marion', all).map((e) => e.id).toSet(),
        {'ocala', 'tuscawilla', 'fountain'});
  });

  test('breadcrumb string', () {
    expect(LocationHierarchy.breadcrumb(city, byId),
        'us › fl › marion › ocala');
  });

  test('cycle-safe: a parent loop does not hang', () {
    final a = _l('a', LocationType.city, parent: 'b');
    final b = _l('b', LocationType.city, parent: 'a');
    final idx = LocationHierarchy.indexById([a, b]);
    // Should terminate and not include a twice.
    final anc = LocationHierarchy.ancestorsOf(a, idx).map((e) => e.id).toList();
    expect(anc, ['b']);
  });
}
