import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config.dart';
import 'package:explorer_os_mobile/features/admin/counties/county_config_repository.dart';
import 'package:explorer_os_mobile/features/events/data/event_repository.dart';
import 'package:explorer_os_mobile/features/gps/utils/geo_math.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/location_engine.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/nearby_gems/data/nearby_gems_repository.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/services/player_location_context.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

const Set<LocationType> _parkAndSpringTypes = {
  LocationType.statePark,
  LocationType.nationalPark,
  LocationType.countyPark,
  LocationType.spring,
};
const Set<LocationType> _townTypes = {LocationType.city, LocationType.community};
const Set<LocationType> _attractionTypes = {
  LocationType.attraction,
  LocationType.museum,
  LocationType.historicSite,
  LocationType.historicDistrict,
  LocationType.scenicOverlook,
  LocationType.hiddenGem,
  LocationType.pointOfInterest,
};

/// Attractions/Historical Sites aren't part of the curated
/// [kActiveLocationTypes] allow-list `nearbyLocationsProvider` enforces (that
/// allow-list also gates the map/GPS-narration/geofence systems, which this
/// change must not touch) — so DISCOVER reads the master `locations` table
/// directly for this one section and ranks it itself with the same
/// [GeoMath] distance math every other nearby feature already uses.
class _NearbyAttraction {
  const _NearbyAttraction(this.location, this.distanceMeters);
  final MasterLocation location;
  final double distanceMeters;
}

const double _kDiscoverRadiusMeters = 20 * 1609.344;

final _nearbyAttractionsProvider = Provider<List<_NearbyAttraction>>((ref) {
  final center = ref.watch(mapCenterProvider);
  if (center == null) return const [];
  final all = ref.watch(masterLocationsProvider).value ?? const [];
  final out = <_NearbyAttraction>[];
  for (final l in all) {
    if (!_attractionTypes.contains(l.type)) continue;
    if (!l.active || l.hidden || !l.hasCoordinates || l.isPublishBlocked) {
      continue;
    }
    final d = GeoMath.distanceMeters(
        center.latitude, center.longitude, l.latitude!, l.longitude!);
    if (d > _kDiscoverRadiusMeters) continue;
    out.add(_NearbyAttraction(l, d));
  }
  out.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return out;
});

/// DISCOVER -- the main nearby-discovery experience, in priority order:
/// GEMS, EVENTS, PARKS & SPRINGS, ATTRACTIONS/HISTORICAL SITES, TOWN, COUNTY.
/// Every section reuses an existing, already-ranked provider (Gems' own
/// featured/priority/popularity/distance ranking, the events/locations
/// nearby lists, the county profile) -- nothing here is a new data source.
/// Tapping a card opens the exact same TELL ME MORE info page the player's
/// own image uses (same [playerContextForLocation]/[playerContextForEvent]/
/// [playerContextForGem]/[playerContextForCounty] builders, same
/// [tellMeMoreResultProvider] lookup), so the listener sees the place's
/// photo, history, and practical info, and hears its recorded narration if
/// one exists.
class NearbyPlacesScreen extends ConsumerWidget {
  const NearbyPlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gems = ref.watch(nearbyGemsForUserProvider);
    final events = ref.watch(nearbyEventsProvider);
    final nearby = ref.watch(nearbyLocationsProvider);
    final parksAndSprings = nearby
        .where((n) => _parkAndSpringTypes.contains(n.location.type))
        .toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    final attractions = ref.watch(_nearbyAttractionsProvider);
    final towns = nearby.where((n) => _townTypes.contains(n.location.type)).toList();

    final county = ref.watch(locationContextProvider).county;
    final countyConfigs =
        ref.watch(countyConfigsProvider).value ?? const <CountyConfig>[];
    CountyConfig? countyConfig;
    if (county != null) {
      final key = county.toLowerCase().trim();
      for (final c in countyConfigs) {
        if (c.key == key) {
          countyConfig = c;
          break;
        }
      }
    }

    final hasAnything = gems.isNotEmpty ||
        events.isNotEmpty ||
        parksAndSprings.isNotEmpty ||
        attractions.isNotEmpty ||
        towns.isNotEmpty ||
        county != null;

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
                        if (parksAndSprings.isNotEmpty)
                          _Section(
                            label: 'PARKS & SPRINGS',
                            children: [
                              for (final n in parksAndSprings)
                                _PlaceCard(
                                  placeContext: playerContextForLocation(
                                      n.location.type == LocationType.spring
                                          ? PlayerLocationKind.spring
                                          : PlayerLocationKind.park,
                                      n),
                                  category: n.location.type.label,
                                ),
                            ],
                          ),
                        if (attractions.isNotEmpty)
                          _Section(
                            label: 'ATTRACTIONS & HISTORICAL SITES',
                            children: [
                              for (final a in attractions)
                                _PlaceCard(
                                  placeContext: playerContextForLocation(
                                      PlayerLocationKind.attraction,
                                      NearbyLocation(
                                          a.location, a.distanceMeters, 0)),
                                  category: a.location.type.label,
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
                        if (county != null)
                          _Section(
                            label: 'COUNTY',
                            children: [
                              _PlaceCard(
                                placeContext: playerContextForCounty(
                                    county, countyConfig),
                                category: 'County',
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
              'Keep driving -- gems, events, parks, springs, attractions, '
              'and towns will show up here as you get near them.',
              textAlign: TextAlign.center,
              style: RD.body,
            ),
          ],
        ),
      ),
    );
  }
}
