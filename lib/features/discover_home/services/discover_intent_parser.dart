import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_home/models/discover_intent.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';

/// Turns a visitor's free-text answer into a [DiscoverIntent]. An interface
/// (not a concrete class) so a future LLM-based parser — e.g. a
/// `discover-intent` edge function using the same OpenAI pattern as
/// `discover-narration` — can be swapped in later via
/// [discoverIntentParserProvider] without any caller change.
abstract class DiscoverIntentParser {
  DiscoverIntent parse(String text);
}

bool _hasAny(String haystack, List<String> phrases) => phrases
    .any((p) => RegExp(r'\b' + RegExp.escape(p) + r'\b').hasMatch(haystack));

/// v1 implementation — a local keyword/phrase heuristic, the same
/// word-boundary-safe technique `interest_tag_mapping.dart` already uses for
/// event tagging (never a substitute for real understanding, just a
/// reasonable default that covers the spec's own examples without a network
/// round-trip for every keystroke's worth of typing).
class KeywordDiscoverIntentParser implements DiscoverIntentParser {
  const KeywordDiscoverIntentParser();

  static const _foodWords = [
    'eat', 'food', 'restaurant', 'restaurants', 'hungry', 'dinner', 'lunch',
    'breakfast', 'coffee', 'dessert', 'somewhere to eat',
  ];
  static const _outdoorWords = [
    'outside', 'outdoor', 'outdoors', 'hike', 'hiking', 'trail', 'trails',
    'nature', 'park', 'spring', 'springs', 'fresh air', 'get out',
  ];
  static const _tonightWords = ['tonight', 'this evening'];
  static const _todayWords = ['today', 'right now'];
  static const _weekendWords = ['weekend', 'saturday', 'sunday'];
  static const _cheapWords = [
    'cheap', 'free', 'inexpensive', 'budget', 'low cost', 'no cost',
  ];
  static const _surpriseWords = [
    'surprise me', 'anything', 'whatever', 'you pick', 'you choose',
    'surprise',
  ];
  static const _undecidedWords = [
    "i don't know", 'dont know', 'not sure', 'no idea', 'idk',
  ];

  /// Free-text keyword → interest token (see `discover_interest.dart`).
  /// Deliberately doesn't cover every interest — only ones with an
  /// unambiguous, commonly-said keyword.
  static const _wordToInterest = <String, String>{
    'wildlife': 'wildlife',
    'animals': 'wildlife',
    'birds': 'birds',
    'birding': 'birds',
    'history': 'history',
    'historic': 'history',
    'museum': 'history',
    'music': 'live_music',
    'concert': 'live_music',
    'live music': 'live_music',
    'festival': 'festivals',
    'shopping': 'shopping',
    'market': 'markets',
    'fish': 'fishing',
    'fishing': 'fishing',
    'boat': 'boating',
    'boating': 'boating',
    'photo': 'photography',
    'photography': 'photography',
    'family': 'family',
    'kids': 'kids',
    'children': 'kids',
    'horse': 'horses_equestrian',
    'horses': 'horses_equestrian',
    'car show': 'cars_trucks',
    'cars': 'cars_trucks',
    'adventure': 'adventure',
    'art': 'arts_culture',
    'craft': 'arts_culture',
    'nightlife': 'nightlife',
  };

  @override
  DiscoverIntent parse(String text) {
    final h = text.toLowerCase().trim();
    if (h.isEmpty) return const DiscoverIntent();

    final kinds = <DiscoverItemKind>{};
    final interests = <String>{};

    if (_hasAny(h, _foodWords)) kinds.add(DiscoverItemKind.gem);
    if (_hasAny(h, _outdoorWords)) {
      kinds.add(DiscoverItemKind.location);
      interests.addAll(const {'outdoors', 'hiking_trails'});
    }
    for (final entry in _wordToInterest.entries) {
      if (RegExp(r'\b' + RegExp.escape(entry.key) + r'\b').hasMatch(h)) {
        interests.add(entry.value);
      }
    }
    if (interests.contains('live_music') || interests.contains('festivals')) {
      kinds.add(DiscoverItemKind.event);
    }

    var timeframe = DiscoverTimeframe.any;
    if (_hasAny(h, _tonightWords)) {
      timeframe = DiscoverTimeframe.tonight;
    } else if (_hasAny(h, _weekendWords)) {
      timeframe = DiscoverTimeframe.weekend;
    } else if (_hasAny(h, _todayWords)) {
      timeframe = DiscoverTimeframe.today;
    }

    return DiscoverIntent(
      kinds: kinds,
      interestTokens: interests,
      timeframe: timeframe,
      priceSensitive: _hasAny(h, _cheapWords),
      surpriseMe: _hasAny(h, _surpriseWords),
      undecided: _hasAny(h, _undecidedWords),
    );
  }
}

final discoverIntentParserProvider = Provider<DiscoverIntentParser>(
  (ref) => const KeywordDiscoverIntentParser(),
);
