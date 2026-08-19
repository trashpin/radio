import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/discover_area/providers/discover_places_provider.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/services/player_location_context.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// DISCOVER -- "what can I discover around me?", answered county-wide: every
/// section below is the full Marion County pool for that category (no town/
/// city/geofence filter), sorted nearest-first via
/// [discover_places_provider.dart]. Category ORDER is fixed and always the
/// same regardless of location: GEMS, EVENTS, LOCAL PARKS, MUSEUMS &
/// HISTORICAL POINTS, SPRINGS, STATE PARKS. Tapping a card opens the exact
/// same TELL ME MORE info page the player's own image uses (same
/// [playerContextForLocation]/[playerContextForEvent]/[playerContextForGem]
/// builders), so the listener sees the place's photo, history, and practical
/// info, and hears its recorded narration if one exists.
class NearbyPlacesScreen extends ConsumerWidget {
  const NearbyPlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gems = ref.watch(discoverGemsProvider);
    final events = ref.watch(discoverEventsProvider);
    final localParks = ref.watch(discoverLocalParksProvider);
    final museumsHistoric = ref.watch(discoverMuseumsHistoricProvider);
    final springs = ref.watch(discoverSpringsProvider);
    final stateParks = ref.watch(discoverStateParksProvider);

    final hasAnything = gems.isNotEmpty ||
        events.isNotEmpty ||
        localParks.isNotEmpty ||
        museumsHistoric.isNotEmpty ||
        springs.isNotEmpty ||
        stateParks.isNotEmpty;

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RadioSubPageBar(
              title: 'Discover',
              subtitle: "What's around you right now",
            ),
            Expanded(
              child: !hasAnything
                  ? const _EmptyState()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(RD.lg, 0, RD.lg, RD.xl),
                      children: [
                        if (gems.isNotEmpty)
                          _Section(
                            label: 'GEMS',
                            children: [
                              for (final g in gems)
                                _PlaceCard(
                                  placeContext: playerContextForGem(
                                      g.gem,
                                      distanceMeters: g.distanceMeters),
                                  category: g.gem.category ?? 'Gem',
                                ),
                            ],
                          ),
                        if (events.isNotEmpty)
                          _Section(
                            label: 'EVENTS',
                            children: [
                              for (final e in events)
                                _PlaceCard(
                                  placeContext: playerContextForEvent(e),
                                  category: 'Event',
                                ),
                            ],
                          ),
                        if (localParks.isNotEmpty)
                          _Section(
                            label: 'LOCAL PARKS',
                            children: [
                              for (final n in localParks)
                                _PlaceCard(
                                  placeContext: playerContextForLocation(
                                      PlayerLocationKind.park, n),
                                  category: n.location.type.label,
                                ),
                            ],
                          ),
                        if (museumsHistoric.isNotEmpty)
                          _Section(
                            label: 'MUSEUMS & HISTORICAL POINTS',
                            children: [
                              for (final n in museumsHistoric)
                                _PlaceCard(
                                  placeContext: playerContextForLocation(
                                      PlayerLocationKind.attraction, n),
                                  category: n.location.type.label,
                                ),
                            ],
                          ),
                        if (springs.isNotEmpty)
                          _Section(
                            label: 'SPRINGS',
                            children: [
                              for (final n in springs)
                                _PlaceCard(
                                  placeContext: playerContextForLocation(
                                      PlayerLocationKind.spring, n),
                                  category: n.location.type.label,
                                ),
                            ],
                          ),
                        if (stateParks.isNotEmpty)
                          _Section(
                            label: 'STATE PARKS',
                            children: [
                              for (final n in stateParks)
                                _PlaceCard(
                                  placeContext: playerContextForLocation(
                                      PlayerLocationKind.park, n),
                                  category: n.location.type.label,
                                ),
                            ],
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RD.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: RD.sectionLabel),
          const SizedBox(height: RD.sm),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: children.length,
              separatorBuilder: (_, _) => const SizedBox(width: RD.md),
              itemBuilder: (_, i) => children[i],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.placeContext, required this.category});

  final PlayerLocationContext placeContext;
  final String category;

  @override
  Widget build(BuildContext context) {
    return StoryCard(
      title: placeContext.title,
      category: category,
      imageUrl: placeContext.imageUrl,
      distanceLabel: placeContext.distanceLabel,
      onTap: () => context.push(
        AppRoute.tellMeMore.path,
        extra: placeContext.tellMeMoreContext,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_rounded, size: 56, color: RD.textSecondary),
            const SizedBox(height: RD.lg),
            Text(
              'Nothing to discover yet',
              textAlign: TextAlign.center,
              style: RD.title.copyWith(fontSize: 20),
            ),
            const SizedBox(height: RD.sm),
            Text(
              "We're still waiting on a GPS fix -- gems, events, parks, "
              'museums, springs, and state parks across Marion County will '
              'show up here once your location is known.',
              textAlign: TextAlign.center,
              style: RD.body,
            ),
          ],
        ),
      ),
    );
  }
}
