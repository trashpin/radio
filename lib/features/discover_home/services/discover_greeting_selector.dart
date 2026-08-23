import 'dart:math';

import 'package:explorer_os_mobile/features/discover_home/models/discover_greeting_context.dart';
import 'package:explorer_os_mobile/features/discover_home/models/discover_greeting_library.dart';

/// How often a personalized (interest/weather/behavior/returning) flavor is
/// used INSTEAD of a plain time/day/generic line, when one is available —
/// spec: "Do not mention interests every time... balance personalization
/// with variety."
const double kDiscoverGreetingPersonalizationChance = 0.4;

/// Picks one opening line for the given [context], avoiding anything in
/// [recentlyUsed] when possible. Pure and deterministic given a fixed
/// [random] — no I/O, no providers — so this is fully unit-testable.
class DiscoverGreetingSelector {
  const DiscoverGreetingSelector();

  DiscoverGreetingTemplate select({
    required DiscoverGreetingContext context,
    List<String> recentlyUsed = const [],
    Random? random,
  }) {
    final rnd = random ?? Random();
    final timeFlavor = _timeFlavor(context.hour);
    final dayFlavor = _dayFlavor(context.weekday);

    final base = discoverGreetingTemplates
        .where((t) =>
            t.flavor == GreetingFlavor.generic ||
            t.flavor == timeFlavor ||
            t.flavor == dayFlavor)
        .toList();

    final flavorPool = <DiscoverGreetingTemplate>[
      if (context.interests.isNotEmpty)
        ...discoverGreetingTemplates.where((t) =>
            t.flavor == GreetingFlavor.interest &&
            context.interests.contains(t.interestToken)),
      if (context.weatherFlavor == WeatherFlavor.good)
        ...discoverGreetingTemplates
            .where((t) => t.flavor == GreetingFlavor.weatherGood),
      if (context.weatherFlavor == WeatherFlavor.rain)
        ...discoverGreetingTemplates
            .where((t) => t.flavor == GreetingFlavor.weatherRain),
      if (context.behaviorFlavor == BehaviorFlavor.gem)
        ...discoverGreetingTemplates
            .where((t) => t.flavor == GreetingFlavor.behaviorGem),
      if (context.behaviorFlavor == BehaviorFlavor.location)
        ...discoverGreetingTemplates
            .where((t) => t.flavor == GreetingFlavor.behaviorLocation),
      if (context.behaviorFlavor == BehaviorFlavor.event)
        ...discoverGreetingTemplates
            .where((t) => t.flavor == GreetingFlavor.behaviorEvent),
      if (context.isReturningVisitor)
        ...discoverGreetingTemplates
            .where((t) => t.flavor == GreetingFlavor.returning),
    ];

    final usePersonalized = flavorPool.isNotEmpty &&
        rnd.nextDouble() < kDiscoverGreetingPersonalizationChance;
    final pool = usePersonalized ? flavorPool : base;

    final fresh = pool.where((t) => !recentlyUsed.contains(t.id)).toList();
    final finalPool = fresh.isNotEmpty ? fresh : pool;

    return finalPool[rnd.nextInt(finalPool.length)];
  }

  GreetingFlavor _timeFlavor(int hour) {
    if (hour < 12) return GreetingFlavor.morning;
    if (hour < 17) return GreetingFlavor.afternoon;
    return GreetingFlavor.evening;
  }

  GreetingFlavor _dayFlavor(int weekday) {
    if (weekday == DateTime.friday) return GreetingFlavor.friday;
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      return GreetingFlavor.weekend;
    }
    return GreetingFlavor.weekday;
  }
}
