import 'package:explorer_os_mobile/features/discover_home/models/discover_intent.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';
import 'package:explorer_os_mobile/features/discover_home/services/discover_intent_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = KeywordDiscoverIntentParser();

  test('"I want to find somewhere to eat" maps to gems', () {
    final i = parser.parse('I want to find somewhere to eat');
    expect(i.kinds, contains(DiscoverItemKind.gem));
  });

  test('"I want to get outside" maps to outdoors + hiking_trails + location', () {
    final i = parser.parse('I want to get outside');
    expect(i.kinds, contains(DiscoverItemKind.location));
    expect(i.interestTokens, containsAll({'outdoors', 'hiking_trails'}));
  });

  test('"What\'s happening tonight?" sets the tonight timeframe', () {
    final i = parser.parse("What's happening tonight?");
    expect(i.timeframe, DiscoverTimeframe.tonight);
  });

  test('"I want something cheap" sets priceSensitive', () {
    final i = parser.parse('I want something cheap');
    expect(i.priceSensitive, isTrue);
  });

  test('"Surprise me" sets surpriseMe', () {
    final i = parser.parse('Surprise me');
    expect(i.surpriseMe, isTrue);
  });

  test('"I don\'t know" sets undecided', () {
    final i = parser.parse("I don't know");
    expect(i.undecided, isTrue);
  });

  test('an empty answer produces an empty intent, never throws', () {
    final i = parser.parse('   ');
    expect(i.isEmpty, isTrue);
  });

  test('word-boundary safe: "quarterly" does not falsely match "art"', () {
    final i = parser.parse('Looking for the quarterly newsletter');
    expect(i.interestTokens, isNot(contains('arts_culture')));
  });

  test('"live music" and "festival" both add event to kinds', () {
    final music = parser.parse('Any live music tonight?');
    expect(music.kinds, contains(DiscoverItemKind.event));
    expect(music.interestTokens, contains('live_music'));

    final fest = parser.parse('Is there a festival this weekend?');
    expect(fest.kinds, contains(DiscoverItemKind.event));
    expect(fest.timeframe, DiscoverTimeframe.weekend);
  });

  group('nightlife/evening-entertainment phrases', () {
    test('"Where can I hear a band?" maps band -> live_music + event', () {
      final i = parser.parse('Where can I hear a band?');
      expect(i.interestTokens, contains('live_music'));
      expect(i.kinds, contains(DiscoverItemKind.event));
    });

    test('"Find me something for date night" maps to nightlife + event', () {
      final i = parser.parse('Find me something for date night');
      expect(i.interestTokens, contains('nightlife'));
      expect(i.kinds, contains(DiscoverItemKind.event));
    });

    test('"Anything happening after 8?" sets the tonight timeframe', () {
      final i = parser.parse('Anything happening after 8?');
      expect(i.timeframe, DiscoverTimeframe.tonight);
    });

    test('"Find something family-friendly tonight" sets tonight + family', () {
      final i = parser.parse('Find something family-friendly tonight');
      expect(i.timeframe, DiscoverTimeframe.tonight);
      expect(i.interestTokens, contains('family'));
    });

    test('"I want dinner and entertainment" maps to gem + event kinds', () {
      final i = parser.parse('I want dinner and entertainment');
      expect(i.kinds, containsAll({DiscoverItemKind.gem, DiscoverItemKind.event}));
      expect(i.interestTokens, contains('nightlife'));
    });

    test('comedy and dancing map to arts_culture (no invented interest token)', () {
      final comedy = parser.parse('Find me a comedy show');
      expect(comedy.interestTokens, contains('arts_culture'));

      final dancing = parser.parse('I want to go dancing');
      expect(dancing.interestTokens, contains('arts_culture'));
    });

    test('karaoke and trivia map to nightlife, the closest real taxonomy token', () {
      final karaoke = parser.parse('Is there karaoke tonight?');
      expect(karaoke.interestTokens, contains('nightlife'));

      final trivia = parser.parse('Any trivia night nearby?');
      expect(trivia.interestTokens, contains('nightlife'));
    });
  });
}
