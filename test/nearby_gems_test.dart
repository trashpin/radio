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
  id: id,
  name: name,
  latitude: lat,
  longitude: lng,
  active: true,
  narrationUrl: 'https://audio/$id.mp3',
);

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

  test('narration_script round-trips through fromJson/toWrite', () {
    final g = NearbyGem.fromJson({
      'id': '1',
      'name': 'Ivy House',
      'narration_script': 'Welcome to the Ivy House, a downtown landmark…',
      'long_story': 'A longer story.',
      'short_description': 'Cozy cafe.',
    });
    expect(g.narrationScript, startsWith('Welcome to the Ivy House'));
    expect(g.toWrite()['narration_script'], g.narrationScript);
  });

  test('narrationText prefers script, then long description, then short', () {
    NearbyGem g({String? script, String? long, String? short}) => NearbyGem(
      id: 'x',
      name: 'X',
      narrationScript: script,
      longStory: long,
      shortDescription: short,
    );

    expect(g(script: 'S', long: 'L', short: 'H').narrationText, 'S');
    expect(g(long: 'L', short: 'H').narrationText, 'L');
    expect(g(short: 'H').narrationText, 'H');
    expect(
      g(script: '   ', long: 'L').narrationText,
      'L',
      reason: 'blank script is skipped',
    );
    expect(g().narrationText, isNull);
  });

  test('canNarrate: audio OR any speakable text (else false)', () {
    NearbyGem g({String? url, String? long}) =>
        NearbyGem(id: 'x', name: 'X', narrationUrl: url, longStory: long);
    expect(g(url: 'https://a.mp3').canNarrate, isTrue); // audio only
    expect(g(long: 'A story to speak').canNarrate, isTrue); // text only
    expect(g(url: '', long: '').canNarrate, isFalse); // nothing
    // hasStory (card enablement) tracks canNarrate now.
    expect(g(long: 'story').hasStory, isTrue);
    expect(g().hasStory, isFalse);
  });

  test(
    'nearbyGemsForUser keeps only in-range gems, sorted nearest-first',
    () async {
      final near = _gem('near', 'Close Cafe', 29.21, -82.06); // ~1.5 km
      final mid = _gem('mid', 'Mid Diner', 29.30, -82.05); // ~11 km
      final far = _gem('far', 'Far Away', 30.20, -82.05); // ~110 km (> 25 mi)
      final noGeo = _gem('nogeo', 'No Coords', null, null);

      final c = ProviderContainer(
        overrides: [
          mapCenterProvider.overrideWith(_FakeCenter.new),
          activeNearbyGemsProvider.overrideWith(
            (ref) async => [far, mid, near, noGeo],
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(activeNearbyGemsProvider.future);
      // Widen to 10 miles so the ~7-mile "mid" gem is in range for this check.
      c.read(nearbyGemsRadiusProvider.notifier).set(kGemsRadius10Mi);

      final hits = c.read(nearbyGemsForUserProvider);
      expect(
        hits.map((h) => h.gem.id),
        ['near', 'mid'],
        reason: 'far (>10mi) and no-coords are excluded; sorted nearest-first',
      );
      expect(hits.first.distanceMeters, lessThan(hits.last.distanceMeters));
    },
  );

  test('default radius is 5 miles; toggle widens to 10 and back', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(nearbyGemsRadiusProvider), kGemsRadius5Mi);
    c.read(nearbyGemsRadiusProvider.notifier).toggle();
    expect(c.read(nearbyGemsRadiusProvider), kGemsRadius10Mi);
    c.read(nearbyGemsRadiusProvider.notifier).toggle();
    expect(c.read(nearbyGemsRadiusProvider), kGemsRadius5Mi);
  });

  test('rankNearbyGems: featured → priority → popularity → distance', () {
    NearbyGem g(
      String id, {
      bool featured = false,
      int priority = 0,
      int popularity = 0,
    }) => NearbyGem(
      id: id,
      name: id,
      latitude: 29.2,
      longitude: -82.05,
      featured: featured,
      priority: priority,
      popularity: popularity,
    );

    final ranked = rankNearbyGems([
      NearbyGemHit(g('nearPlain'), 500),
      NearbyGemHit(g('farFeatured', featured: true), 9000),
      NearbyGemHit(g('midPriority', priority: 5), 3000),
      NearbyGemHit(g('midPopular', popularity: 99), 3000),
    ]);
    expect(ranked.map((h) => h.gem.id), [
      'farFeatured',
      'midPriority',
      'midPopular',
      'nearPlain',
    ]);
  });
}
