import 'package:explorer_os_mobile/features/discover_home/models/interest_tag_mapping.dart';
import 'package:explorer_os_mobile/features/events/models/local_event.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:flutter_test/flutter_test.dart';

LocalEvent _event({
  String name = 'Untitled',
  String? description,
  String? category,
  List<String> interestTags = const [],
}) =>
    LocalEvent(
      id: 'e1',
      name: name,
      description: description,
      category: category,
      interestTags: interestTags,
    );

void main() {
  group('interestTagsForLocationType', () {
    test('a spring maps to springs_water/outdoors/adventure', () {
      expect(interestTagsForLocationType(LocationType.spring),
          {'springs_water', 'outdoors', 'adventure'});
    });

    test('an administrative type (county) maps to nothing', () {
      expect(interestTagsForLocationType(LocationType.county), isEmpty);
    });
  });

  group('interestTagsForGemCategory', () {
    test('Shopping maps to shopping/markets', () {
      expect(interestTagsForGemCategory('Shopping'), {'shopping', 'markets'});
    });

    test('an unmapped food category (Restaurant) maps to nothing — disclosed gap', () {
      expect(interestTagsForGemCategory('Restaurant'), isEmpty);
    });
  });

  group('interestTagsForEvent', () {
    test('explicit interest_tags column is always included', () {
      final e = _event(interestTags: const ['fishing']);
      expect(interestTagsForEvent(e), contains('fishing'));
    });

    test('keyword heuristic infers from name/description when nothing is explicitly tagged', () {
      final e = _event(name: 'Downtown Farmers Market');
      expect(interestTagsForEvent(e), containsAll({'markets', 'free_things'}));
    });

    test('an event with no matching keywords and no tags yields no interests', () {
      final e = _event(name: 'Quarterly Board Meeting');
      expect(interestTagsForEvent(e), isEmpty);
    });
  });
}
