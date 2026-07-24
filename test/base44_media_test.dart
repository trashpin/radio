import 'package:flutter_test/flutter_test.dart';

import 'package:explorer_os_mobile/features/media/models/media_item.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';
import 'package:explorer_os_mobile/shared/models/radio_station.dart';

void main() {
  group('Destination.fromJson maps the Base44 destinations schema', () {
    test('reads destination_id / hero_image / destination_type', () {
      final d = Destination.fromJson({
        'destination_id': 'abc-123',
        'name': 'Ocala National Forest',
        'description': 'Springs and scrub.',
        'hero_image': 'https://img/hero.jpg',
        'destination_type': 'National Forest',
        'state_province': 'Florida',
        'country': 'USA',
        'featured': true,
      });

      expect(d.id, 'abc-123');
      expect(d.name, 'Ocala National Forest');
      expect(d.imageUrl, 'https://img/hero.jpg');
      expect(d.category, 'National Forest');
      expect(d.location, 'Florida, USA');
      expect(d.featured, isTrue);
    });

    test('still accepts legacy keys (seed/preview data)', () {
      final d = Destination.fromJson({
        'id': 'legacy-1',
        'name': 'Legacy Park',
        'image_url': 'https://img/legacy.jpg',
        'category': 'park',
        'location': 'Somewhere',
        'is_featured': true,
      });

      expect(d.id, 'legacy-1');
      expect(d.imageUrl, 'https://img/legacy.jpg');
      expect(d.category, 'park');
      expect(d.location, 'Somewhere');
      expect(d.featured, isTrue);
    });
  });

  group('MediaItem maps the Base44 media schema', () {
    test('detects audio by media_type and maps to a Song', () {
      final m = MediaItem.fromJson({
        'media_id': 'm-1',
        'destination_id': 'dest-1',
        'media_type': 'audio',
        'title': 'Trailhead Theme',
        'file_url': 'demo/track_trailhead.mp3',
        'published': true,
        'sort_order': 0,
      });

      expect(m.id, 'm-1');
      expect(m.isAudio, isTrue);

      final song = m.toSong('dest-1', resolvedUrl: 'https://cdn/x.mp3');
      expect(song.stationId, 'dest-1');
      expect(song.title, 'Trailhead Theme');
      expect(song.audioUrl, 'https://cdn/x.mp3');
    });

    test('detects audio by file extension when media_type is generic', () {
      final m = MediaItem.fromJson({
        'media_id': 'm-2',
        'media_type': 'file',
        'file_url': 'https://cdn/song.m4a',
      });
      expect(m.isAudio, isTrue);
    });

    test('non-audio media (photo) is excluded', () {
      final m = MediaItem.fromJson({
        'media_id': 'm-3',
        'media_type': 'photo',
        'file_url': 'https://cdn/pic.jpg',
      });
      expect(m.isAudio, isFalse);
    });
  });

  test('RadioStation.fromDestination derives a station from a destination', () {
    final station = RadioStation.fromDestination(const Destination(
      id: 'dest-1',
      name: 'Ocala National Forest',
      description: 'Springs.',
      imageUrl: 'https://img/hero.jpg',
    ));

    expect(station.id, 'dest-1');
    expect(station.name, 'Ocala National Forest Radio');
    expect(station.destinationId, 'dest-1');
    expect(station.imageUrl, 'https://img/hero.jpg');
  });
}
