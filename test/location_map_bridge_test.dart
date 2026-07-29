import 'package:explorer_os_mobile/features/locations/data/location_map_bridge.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/maps/marker_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nearbyTokenFor', () {
    test('maps master types onto existing legend/style tokens', () {
      expect(nearbyTokenFor(LocationType.spring), 'springs');
      expect(nearbyTokenFor(LocationType.trailhead), 'trails');
      expect(nearbyTokenFor(LocationType.historicDistrict), 'historic_sites');
      expect(nearbyTokenFor(LocationType.scenicOverlook), 'scenic_overlooks');
      expect(nearbyTokenFor(LocationType.county), 'cities');
      expect(nearbyTokenFor(LocationType.wildlifeViewing), 'wildlife');
    });

    test('every token resolves to a concrete (non-Other) marker style', () {
      for (final t in [
        LocationType.spring,
        LocationType.trail,
        LocationType.historicSite,
        LocationType.scenicOverlook,
        LocationType.visitorCenter,
        LocationType.campground,
        LocationType.parking,
        LocationType.wildlifeViewing,
        LocationType.city,
      ]) {
        // The map colors places via markerStyleForItem (category + name).
        final style = markerStyleForItem(nearbyTokenFor(t), t.label);
        expect(style.key, isNot('other'),
            reason: '${t.id} should color a real marker');
      }
    });
  });

  group('masterToNearby', () {
    test('carries id, coords, media, and category token', () {
      final l = MasterLocation(
        id: 'abc',
        name: 'Silver Springs',
        type: LocationType.spring,
        latitude: 29.2,
        longitude: -82.0,
        images: const ['http://x/ss.jpg'],
        audioFiles: const ['http://x/ss.mp3'],
        featured: true,
      );
      final n = masterToNearby(l);
      expect(n.id, 'locations:abc');
      expect(n.category, 'springs');
      expect(n.latitude, 29.2);
      expect(n.imageUrl, 'http://x/ss.jpg');
      expect(n.audioUrl, 'http://x/ss.mp3');
      expect(n.featured, isTrue);
      // The map colors it as a spring, not the generic fallback.
      expect(markerStyleForItem(n.category, n.name, n.subcategory).key,
          'springs');
    });
  });
}
