import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/events/data/event_repository.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/services/player_location_context.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

const Set<LocationType> _parkTypes = {
  LocationType.statePark,
  LocationType.nationalPark,
  LocationType.countyPark,
};
const Set<LocationType> _townTypes = {LocationType.city, LocationType.community};

/// DISCOVER -- every event, park, spring, and town currently nearby, each as
/// a tappable photo card. Tapping one opens the exact same TELL ME MORE info
/// page the player's own image uses (same [playerContextForLocation] /
/// [playerContextForEvent] builders, same [tellMeMoreResultProvider] lookup),
/// so the listener sees the place's photo, history, and practical info, and
/// hears its recorded narration if one exists -- reusing TELL ME MORE rather
/// than a second info/audio system.
class NearbyPlacesScreen extends ConsumerWidget {
  const NearbyPlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(nearbyEventsProvider);
    final nearby = ref.watch(nearbyLocationsProvider);
    final parks = nearby.where((n) => _parkTypes.contains(n.location.type)).toList();
    final springs =
        nearby.where((n) => n.location.type == LocationType.spring).toList();
    final towns = nearby.where((n) => _townTypes.contains(n.location.type)).toList();

    final hasAnything =
        events.isNotEmpty || parks.isNotEmpty || springs.isNotEmpty || towns.isNotEmpty;

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
                        if (parks.isNotEmpty)
                          _Section(
                            label: 'PARKS',
                            children: [
                              for (final n in parks)
                                _PlaceCard(
                                  placeContext: playerContextForLocation(
                                      PlayerLocationKind.park, n),
                                  category: 'Park',
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
                                  category: 'Spring',
                                ),
                            ],
                          ),
                        if (towns.isNotEmpty)
                          _Section(
                            label: 'TOWNS',
                            children: [
                              for (final n in towns)
                                _PlaceCard(
                                  placeContext: playerContextForLocation(
                                      PlayerLocationKind.town, n),
                                  category: 'Town',
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
              'Nothing nearby yet',
              textAlign: TextAlign.center,
              style: RD.title.copyWith(fontSize: 20),
            ),
            const SizedBox(height: RD.sm),
            Text(
              'Keep driving -- events, parks, springs, and towns will show up '
              'here as you get near them.',
              textAlign: TextAlign.center,
              style: RD.body,
            ),
          ],
        ),
      ),
    );
  }
}
