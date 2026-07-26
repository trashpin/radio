import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';
import 'package:explorer_os_mobile/features/maps/providers/map_places_provider.dart';

void main() {
  test('maps POI rows with latitude/longitude', () {
    final rows = [
      {
        'id': '1',
        'name': 'Juniper Springs',
        'category': 'springs',
        'latitude': 29.18,
        'longitude': -81.71,
      },
    ];
    final places = mapPlacesFromRows(rows, table: 'map_locations');
    expect(places, hasLength(1));
    expect(places.first.name, 'Juniper Springs');
    expect(places.first.category, 'springs');
    expect(places.first.latitude, 29.18);
    expect(places.first.longitude, -81.71);
    expect(places.first.id, 'map_locations:1');
  });

  test('forces the campgrounds category so it gets the campground icon', () {
    final rows = [
      {'id': 'c1', 'name': 'Juniper Campground', 'latitude': 29.18, 'longitude': -81.71},
    ];
    final places =
        mapPlacesFromRows(rows, table: 'campgrounds', forcedCategory: 'campgrounds');
    expect(places, hasLength(1));
    expect(places.first.category, 'campgrounds');
  });

  test('accepts lat/lng and lat/lon field names, and string coordinates', () {
    final rows = [
      {'id': 'a', 'name': 'A', 'lat': 29.1, 'lng': -81.7},
      {'id': 'b', 'name': 'B', 'lat': 29.2, 'lon': -81.6},
      {'id': 'c', 'name': 'C', 'latitude': '29.3', 'longitude': '-81.5'},
    ];
    final places = mapPlacesFromRows(rows, table: 'map_locations');
    expect(places, hasLength(3));
    expect(places[0].longitude, -81.7);
    expect(places[1].longitude, -81.6);
    expect(places[2].latitude, 29.3);
  });

  test('skips rows with missing / 0,0 / out-of-range coordinates', () {
    final rows = [
      {'id': '1', 'name': 'no coords'},
      {'id': '2', 'name': 'zero', 'latitude': 0, 'longitude': 0},
      {'id': '3', 'name': 'bad', 'latitude': 999, 'longitude': -81.7},
      {'id': '4', 'name': 'good', 'latitude': 29.2, 'longitude': -81.7},
    ];
    final places = mapPlacesFromRows(rows, table: 'map_locations');
    expect(places, hasLength(1));
    expect(places.first.name, 'good');
  });

  test('NearbyItem.fromJson also honors lat/lng/lon fallbacks', () {
    final a = NearbyItem.fromJson({'id': '1', 'name': 'A', 'lat': 1.0, 'lng': 2.0});
    expect(a.latitude, 1.0);
    expect(a.longitude, 2.0);
    final b = NearbyItem.fromJson(
        {'id': '2', 'name': 'B', 'latitude': '3.5', 'lon': '4.5'});
    expect(b.latitude, 3.5);
    expect(b.longitude, 4.5);
  });
}
