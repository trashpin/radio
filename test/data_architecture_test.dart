// Unit tests for the platform data layer: the generic in-memory cache and a
// couple of representative model mappers (including the polymorphic
// favorite/download entity-type tokens). These exercise the reusable pieces
// without needing a live Supabase connection.

import 'package:explorer_os_mobile/core/data/cache_store.dart';
import 'package:explorer_os_mobile/shared/models/download.dart';
import 'package:explorer_os_mobile/shared/models/park.dart';
import 'package:explorer_os_mobile/shared/models/user_favorite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryCacheStore', () {
    test('distinguishes "never cached" from "cached empty"', () {
      final cache = InMemoryCacheStore<Park>();
      expect(cache.readAll(), isNull);

      cache.writeAll(const []);
      expect(cache.readAll(), isEmpty);
    });

    test('writeAll / readById / upsert / remove / clear', () {
      final cache = InMemoryCacheStore<Park>();
      const a = Park(id: '1', destinationId: 'd', name: 'A');
      const b = Park(id: '2', destinationId: 'd', name: 'B');

      cache.writeAll(const [a]);
      expect(cache.readById('1'), a);
      expect(cache.readById('2'), isNull);

      cache.upsert(b);
      expect(cache.readAll(), containsAll(<Park>[a, b]));

      cache.remove('1');
      expect(cache.readById('1'), isNull);

      cache.clear();
      expect(cache.readAll(), isNull);
    });
  });

  group('model mapping', () {
    test('Park.fromJson maps snake_case foreign keys', () {
      final park = Park.fromJson(const {
        'id': 7,
        'destination_id': 'dest-1',
        'name': 'Ocala National Forest',
        'image_url': 'https://example.com/x.jpg',
      });
      expect(park.id, '7');
      expect(park.destinationId, 'dest-1');
      expect(park.name, 'Ocala National Forest');
      expect(park.imageUrl, 'https://example.com/x.jpg');
    });

    test('UserFavorite round-trips entity type token', () {
      final fav = UserFavorite.fromJson(const {
        'id': 'f1',
        'user_id': 'u1',
        'entity_type': 'radio_station',
        'entity_id': 's1',
      });
      expect(fav.entityType, FavoriteEntityType.radioStation);
      expect(fav.toJson()['entity_type'], 'radio_station');
    });

    test('Download maps status + progress and toJson', () {
      final dl = Download.fromJson(const {
        'id': 'd1',
        'entity_type': 'park',
        'entity_id': 'p1',
        'status': 'completed',
        'progress': 1.0,
      });
      expect(dl.status, DownloadStatus.completed);
      expect(dl.isComplete, isTrue);
      expect(dl.toJson()['status'], 'completed');
    });
  });
}
