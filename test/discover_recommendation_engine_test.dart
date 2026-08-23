import 'package:explorer_os_mobile/features/discover_home/models/discover_intent.dart';
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
  String? timeOfDay,
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
    timeOfDay: timeOfDay,
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

    test('tonight only includes today\'s events genuinely classified evening/late_night, '
        'never a same-day event whose time is merely unknown or daytime '
        '(the 2 PM vs 7 PM concert distinction)', () {
      final now = DateTime(2026, 8, 15);
      final afternoonShow = _item(
          id: 'matinee', title: 'Matinee', kind: DiscoverItemKind.event,
          eventDate: now, timeOfDay: 'afternoon');
      final eveningShow = _item(
          id: 'evening', title: 'Evening Show', kind: DiscoverItemKind.event,
          eventDate: now, timeOfDay: 'evening');
      final lateShow = _item(
          id: 'late', title: 'Late Show', kind: DiscoverItemKind.event,
          eventDate: now, timeOfDay: 'late_night');
      final unknownTimeShow = _item(
          id: 'unknown', title: 'Mystery Time', kind: DiscoverItemKind.event,
          eventDate: now, timeOfDay: null);
      final tomorrowEvening = _item(
          id: 'tomorrow', title: 'Tomorrow', kind: DiscoverItemKind.event,
          eventDate: now.add(const Duration(days: 1)), timeOfDay: 'evening');
      final result = engine.tonight(
        [afternoonShow, eveningShow, lateShow, unknownTimeShow, tomorrowEvening],
        now: now,
      );
      expect(result.map((i) => i.id).toSet(), {'evening', 'late'});
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

  group('respondToIntent', () {
    test('a gem-kind intent (e.g. "somewhere to eat") only returns gems', () {
      final gem = _item(id: 'g', title: 'Diner', kind: DiscoverItemKind.gem);
      final park = _item(id: 'p', title: 'Park', kind: DiscoverItemKind.location);
      final result = engine.respondToIntent(
        [gem, park],
        const DiscoverIntent(kinds: {DiscoverItemKind.gem}),
        const {},
      );
      expect(result.map((i) => i.id), ['g']);
    });

    test('interest tokens from the intent override the visitor\'s standing interests', () {
      final fishing = _item(id: 'f', title: 'Lake', interests: const {'fishing'});
      final history = _item(id: 'h', title: 'Fort', interests: const {'history'});
      final result = engine.respondToIntent(
        [fishing, history],
        const DiscoverIntent(interestTokens: {'fishing'}),
        const {'history'}, // standing interests — should NOT win here
      );
      expect(result.first.id, 'f');
    });

    test('price-sensitive answers prefer items tagged free_things when scores tie', () {
      final free = _item(id: 'free', title: 'Free Thing', interests: const {'free_things', 'outdoors'});
      final paid = _item(id: 'paid', title: 'Paid Thing', interests: const {'outdoors'});
      final result = engine.respondToIntent(
        [paid, free],
        const DiscoverIntent(interestTokens: {'outdoors'}, priceSensitive: true),
        const {},
      );
      expect(result.first.id, 'free');
    });

    test('"I don\'t know" returns a mix rather than one narrow list', () {
      final picked = _item(id: 'picked', title: 'Picked', interests: const {'history'}, featured: true);
      final near = _item(id: 'near', title: 'Near', distanceMeters: 50);
      final result = engine.respondToIntent(
        [picked, near],
        const DiscoverIntent(undecided: true),
        const {'history'},
      );
      expect(result.map((i) => i.id).toSet(), {'picked', 'near'});
    });

    test('an unmatched intent never returns empty — falls back to nearYou', () {
      final only = _item(id: 'only', title: 'Only', interests: const {'shopping'}, distanceMeters: 10);
      final result = engine.respondToIntent(
        [only],
        const DiscoverIntent(interestTokens: {'nonexistent_token'}),
        const {},
      );
      expect(result, isNotEmpty);
    });

    test('a same-day timeframe with no kind restriction only returns today\'s events', () {
      final now = DateTime(2026, 8, 15);
      final todayEvent = _item(id: 'e1', title: 'Fair', kind: DiscoverItemKind.event, eventDate: now);
      final park = _item(id: 'p', title: 'Park', kind: DiscoverItemKind.location);
      final result = engine.respondToIntent(
        [todayEvent, park],
        const DiscoverIntent(timeframe: DiscoverTimeframe.today),
        const {},
        now: now,
      );
      expect(result.map((i) => i.id), ['e1']);
    });
  });
}
