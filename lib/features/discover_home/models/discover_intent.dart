import 'package:explorer_os_mobile/features/discover_home/models/discoverable_item.dart';

enum DiscoverTimeframe { any, today, tonight, weekend }

/// What a visitor's free-text (or, later, voice) answer to the opening
/// question means for the recommendation engine — spec: "the user's response
/// should eventually drive Discover recommendations." Produced by whatever
/// implements `DiscoverIntentParser`; consumed by
/// `DiscoverRecommendationEngine.respondToIntent`. Neither side needs to know
/// how the other is implemented, so a future LLM-based parser (or voice
/// transcript) can replace [KeywordDiscoverIntentParser] without touching
/// the engine or UI.
class DiscoverIntent {
  const DiscoverIntent({
    this.kinds = const {},
    this.interestTokens = const {},
    this.timeframe = DiscoverTimeframe.any,
    this.priceSensitive = false,
    this.surpriseMe = false,
    this.undecided = false,
  });

  final Set<DiscoverItemKind> kinds;
  final Set<String> interestTokens;
  final DiscoverTimeframe timeframe;
  final bool priceSensitive;
  final bool surpriseMe;
  final bool undecided;

  bool get isEmpty =>
      kinds.isEmpty &&
      interestTokens.isEmpty &&
      timeframe == DiscoverTimeframe.any &&
      !priceSensitive &&
      !surpriseMe &&
      !undecided;
}
