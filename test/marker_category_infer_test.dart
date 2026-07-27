import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/maps/marker_category_infer.dart';

void main() {
  String infer(String? cat, String? name, [String? sub]) =>
      inferCategoryKey(cat, name, sub);

  test('explicit legend tokens are honored', () {
    expect(infer('springs', 'Anything'), 'springs');
    expect(infer('visitor_centers', 'X'), 'visitor_centers');
    expect(infer('wildlife_viewing', 'X'), 'wildlife_viewing');
  });

  test('infers from the name when category is generic/null', () {
    expect(infer(null, 'Silver Glen Springs'), 'springs');
    expect(infer('Spring Park', 'Alexander Spring'), 'springs');
    expect(infer(null, 'Fort King Historic Site'), 'historic_sites');
    expect(infer(null, 'Volusia Bar Lighthouse'), 'historic_sites');
    expect(infer(null, 'Centennial OHV Trailhead'), 'trailheads');
    expect(infer(null, 'North Loop Trail'), 'trailheads');
    expect(infer(null, 'Ocala Visitor Center'), 'visitor_centers');
    expect(infer(null, 'Yearling Ridge Overlook'), 'scenic_overlooks');
    expect(infer('Coastal Park', 'Bird Creek Beach'), 'scenic_overlooks');
    expect(infer(null, 'Day-Use Parking Lot'), 'parking');
    expect(infer(null, 'Bear Viewing Area / wildlife'), 'wildlife_viewing');
    expect(infer(null, 'Flash Flood Warning Zone'), 'safety_alerts');
  });

  test('specific facilities win over generic water/scenery', () {
    // Has both "spring" and "campground" -> campground.
    expect(infer(null, 'Juniper Springs Campground'), 'campgrounds');
    // Has both "spring" and "overlook" -> overlook.
    expect(infer(null, 'Salt Springs Overlook'), 'scenic_overlooks');
  });

  test('unknown/empty falls back to other', () {
    expect(infer(null, null), 'other');
    expect(infer('', ''), 'other');
    expect(infer('poi', 'Woody Truck Sales'), 'other');
  });

  test('every result is a valid legend key', () {
    for (final name in ['Spring', 'Trail', 'Fort', 'Random Place', null]) {
      expect(markerCategoryKeys.contains(infer(null, name)), isTrue);
    }
  });
}
