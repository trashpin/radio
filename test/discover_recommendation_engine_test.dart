import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';
import 'package:explorer_os_mobile/features/discover_home/services/discover_recommendation_engine.dart';
import 'package:explorer_os_mobile/features/radio/models/geo_point.dart';
import 'package:explorer_os_mobile/features/radio/models/tell_me_more_context.dart';
import 'package:explorer_os_mobile/features/radio/services/player_location_context.dart';
import 'package:flutter_test/flutter_test.dart';

DiscoverableItem _item({
  required String id,
  required String title,
  Set<String> interests = const {},
  double? distanceMeters,
  DateTime? eventDate,
  bool featured = false,
  int priority = 0,
  DiscoverItemKind kind = DiscoverItemKind.location,
}) {
  final context = PlayerLocationContext(
    kind: PlayerLocationKind.park,
    title: title,
    distanceLabel: distanceMeters == null ? null : '${distanceMeters.round()}m',
    tellMeMoreContext: TellMeMoreContext(subject: title, locationId: id, location: const GeoPoint(latitude: 1, longitude: 1)),
  );
  return DiscoverableItem(
    kind: kind,
    id: id,
    title: title,
    interestTags: interests,
    context: context,
    distanceMeters: distanceMeters,
    eventDate: eventDate,
    featured: featured,
    priority: priority,
  );
}

void main() {
  const engine = DiscoverRecommendationEngine();

  group('pickedForYou', () {
    test('ranks by number of matched interests first', () {
      final a = _item(id: 'a', title: 'A', interests: {'history'});
      final b = _item(id: 'b', title: 'B', interests: {'history', 'outdoors'});
      final result = engine.pickedForYou([a, b], {'history', 'outdoors'});
      expect(result.first.item.id, 'b');
      expect(result.first.matchedInterests, {'history', 'outdoors'});
    });

    test('excludes items matching none of the selected interests', () {
      final a = _item(id: 'a', title: 'A', interests: {'shopping'});
      final result = engine.pickedForYou([a], {'history'});
      expect(result, isEmpty);
    });

    test('falls back to an editorial ranking when no interests are selected', () {
      final a = _item(id: 'a', title: 'A', featured: false, priority: 0);
      final b = _item(id: 'b', title: 'B', featured: true, priority: 0);
      final result = engine.pickedForYou([a, b], const {});
      expect(result.first.item.id, 'b');
      expect(result.first.matchedInterests, isEmpty);
    });
  });

  group('today / thisWeekend', () {
    test('today only includes events dated today', () {
      final now = DateTime(2026, 8, 15); // a Saturday
      final todayEvent = _item(
        id: 'e1', title: 'Fair', kind: DiscoverItemKind.event, eventDate: now);
      final tomorrowEvent = _item(
        id: 'e2', title: 'Concert', kind: DiscoverItemKind.event,
        eventDate: now.add(const Duration(days: 1)));
      final result = engine.today([todayEvent, tomorrowEvent], now: now);
      expect(result.map((i) => i.id), ['e1']);
    });

    test('thisWeekend includes the upcoming Saturday and Sunday', () {
      final monday = DateTime(2026, 8, 17); // a Monday
      final saturday = monday.add(const Duration(days: 5));
      final sunday = monday.add(const Duration(days: 6));
      final nextMonday = monday.add(const Duration(days: 7));
      final satEvent = _item(id: 'sat', title: 'Sat', kind: DiscoverItemKind.event, eventDate: saturday);
      final sunEvent = _item(id: 'sun', title: 'Sun', kind: DiscoverItemKind.event, eventDate: sunday);
      final farEvent = _item(id: 'far', title: 'Far', kind: DiscoverItemKind.event, eventDate: nextMonday);
      final result = engine.thisWeekend([satEvent, sunEvent, farEvent], now: monday);
      expect(result.map((i) => i.id).toSet(), {'sat', 'sun'});
    });

    test('thisWeekend includes today when today already is Saturday or Sunday', () {
      final saturday = DateTime(2026, 8, 15);
      final todayEvent =
          _item(id: 'today', title: 'Today', kind: DiscoverItemKind.event, eventDate: saturday);
      final result = engine.thisWeekend([todayEvent], now: saturday);
      expect(result.map((i) => i.id), ['today']);
    });
  });

  group('nearYou', () {
    test('sorts nearest first and respects the limit', () {
      final far = _item(id: 'far', title: 'Far', distanceMeters: 5000);
      final near = _item(id: 'near', title: 'Near', distanceMeters: 100);
      final result = engine.nearYou([far, near], limit: 1);
      expect(result.map((i) => i.id), ['near']);
    });

    test('items with no distance never crash and sort last', () {
      final unknown = _item(id: 'u', title: 'Unknown', distanceMeters: null);
      final known = _item(id: 'k', title: 'Known', distanceMeters: 10);
      final result = engine.nearYou([unknown, known]);
      expect(result.map((i) => i.id), ['k', 'u']);
    });
  });

  group('youMightLike', () {
    test('excludes items already shown elsewhere', () {
      final a = _item(id: 'a', title: 'A');
      final b = _item(id: 'b', title: 'B');
      final result = engine.youMightLike([a, b], const {}, {'a'});
      expect(result.map((i) => i.id), ['b']);
    });

    test('boosts partial interest overlap even when it did not qualify for PICKED FOR YOU', () {
      final noMatch = _item(id: 'none', title: 'None', interests: const {});
      final partial = _item(id: 'partial', title: 'Partial', interests: {'birds'});
      final result = engine.youMightLike([noMatch, partial], {'birds', 'history'}, const {});
      expect(result.first.id, 'partial');
    });
  });
}
