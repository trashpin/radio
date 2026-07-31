import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/nearby_gems/data/nearby_gems_repository.dart';
import 'package:explorer_os_mobile/features/nearby_gems/models/nearby_gem.dart';

class _FakeCenter extends MapCenter {
  @override
  LatLng? build() => const LatLng(29.20, -82.05); // Ocala area
}

NearbyGem _gem(String id, String name, double? lat, double? lng) => NearbyGem(
      id: id, name: name, latitude: lat, longitude: lng, active: true,
      narrationUrl: 'https://audio/$id.mp3');

void main() {
  test('model parses snake_case + arrays', () {
    final g = NearbyGem.fromJson({
      'id': '1',
      'name': 'Ivy House',
      'category': 'Restaurant',
      'badge': 'Local Favorite',
      'featured_image': 'https://img/hero.jpg',
      'gallery_images': ['https://img/a.jpg', 'https://img/b.jpg'],
      'latitude': 29.2,
      'longitude': -82.05,
      'narration_url': 'https://audio/1.mp3',
      'active': true,
    });
    expect(g.name, 'Ivy House');
    expect(g.badge, 'Local Favorite');
    expect(g.galleryImages, hasLength(2));
    expect(g.hasCoordinates, isTrue);
    expect(g.hasStory, isTrue);
  });

  test('nearbyGemsForUser keeps only in-range gems, sorted nearest-first', () async {
    final near = _gem('near', 'Close Cafe', 29.21, -82.06); // ~1.5 km
    final mid = _gem('mid', 'Mid Diner', 29.30, -82.05); // ~11 km
    final far = _gem('far', 'Far Away', 30.20, -82.05); // ~110 km (> 25 mi)
    final noGeo = _gem('nogeo', 'No Coords', null, null);

    final c = ProviderContainer(overrides: [
      mapCenterProvider.overrideWith(_FakeCenter.new),
      activeNearbyGemsProvider
          .overrideWith((ref) async => [far, mid, near, noGeo]),
    ]);
    addTearDown(c.dispose);
    await c.read(activeNearbyGemsProvider.future);

    final hits = c.read(nearbyGemsForUserProvider);
    expect(hits.map((h) => h.gem.id), ['near', 'mid'],
        reason: 'far (>25mi) and no-coords are excluded; sorted nearest-first');
    expect(hits.first.distanceMeters, lessThan(hits.last.distanceMeters));
  });
}
