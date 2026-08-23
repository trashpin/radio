import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_story_type.dart';
import 'package:explorer_os_mobile/features/ocala_forest/tour/models/tour_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TourStoryType.fromStoryCategory', () {
    test('maps known categories', () {
      expect(TourStoryType.fromStoryCategory('HISTORY'), TourStoryType.verifiedHistory);
      expect(TourStoryType.fromStoryCategory('wildlife'), TourStoryType.wildlife);
      expect(TourStoryType.fromStoryCategory('Folklore'), TourStoryType.folklore);
      expect(TourStoryType.fromStoryCategory('legend'), TourStoryType.legend);
      expect(TourStoryType.fromStoryCategory('unverified'), TourStoryType.unverified);
    });

    test('defaults null/unknown/empty to localStory, never verified', () {
      expect(TourStoryType.fromStoryCategory(null), TourStoryType.localStory);
      expect(TourStoryType.fromStoryCategory(''), TourStoryType.localStory);
      expect(TourStoryType.fromStoryCategory('something_new'), TourStoryType.localStory);
    });

    test('isUnverified is true only for folklore/legend/unverified', () {
      expect(TourStoryType.folklore.isUnverified, isTrue);
      expect(TourStoryType.legend.isUnverified, isTrue);
      expect(TourStoryType.unverified.isUnverified, isTrue);
      expect(TourStoryType.verifiedHistory.isUnverified, isFalse);
      expect(TourStoryType.localStory.isUnverified, isFalse);
      expect(TourStoryType.general.isUnverified, isFalse);
    });
  });

  group('TourType.matches', () {
    test('general accepts everything', () {
      expect(TourType.general.matches('anything', TourStoryType.general), isTrue);
    });

    test('birding only matches bird-related categories', () {
      expect(TourType.birding.matches('Bird Habitat', TourStoryType.general), isTrue);
      expect(TourType.birding.matches('Spring', TourStoryType.general), isFalse);
    });

    test('springsWater matches water categories or geology story type', () {
      expect(TourType.springsWater.matches('Spring', TourStoryType.general), isTrue);
      expect(TourType.springsWater.matches('Lake', TourStoryType.general), isTrue);
      expect(TourType.springsWater.matches('Rock Formation', TourStoryType.geology), isTrue);
      expect(TourType.springsWater.matches('Historic Site', TourStoryType.verifiedHistory), isFalse);
    });

    test('history matches verified history content or historic-named categories', () {
      expect(TourType.history.matches('Anything', TourStoryType.verifiedHistory), isTrue);
      expect(TourType.history.matches('Historic Cabin', TourStoryType.general), isTrue);
      expect(TourType.history.matches('Spring', TourStoryType.general), isFalse);
    });

    test('folklore tour only matches unverified content, regardless of category', () {
      expect(TourType.folklore.matches('Spring', TourStoryType.folklore), isTrue);
      expect(TourType.folklore.matches('Spring', TourStoryType.verifiedHistory), isFalse);
    });
  });
}
