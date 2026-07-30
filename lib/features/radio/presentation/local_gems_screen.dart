import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/location_engine.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/locations/presentation/destination_detail_card.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// A Local Gems category: matches nearby locations by [types] and/or [keywords].
class _GemCategory {
  const _GemCategory(this.label, this.icon,
      {this.types = const {}, this.keywords = const []});
  final String label;
  final IconData icon;
  final Set<LocationType> types;
  final List<String> keywords;

  bool matches(MasterLocation l) {
    if (types.isEmpty && keywords.isEmpty) return true; // "All"
    if (types.contains(l.type)) return true;
    final hay = '${l.name} ${l.description ?? ''}'.toLowerCase();
    return keywords.any(hay.contains);
  }
}

const _categories = <_GemCategory>[
  _GemCategory('All', Icons.explore_rounded),
  _GemCategory('Restaurants', Icons.restaurant_rounded,
      types: {LocationType.restaurant}, keywords: ['grill', 'diner', 'kitchen', 'bbq']),
  _GemCategory('Coffee', Icons.local_cafe_rounded,
      keywords: ['coffee', 'cafe', 'café', 'espresso', 'roaster']),
  _GemCategory('Ice Cream', Icons.icecream_rounded,
      keywords: ['ice cream', 'creamery', 'gelato', 'frozen', 'scoop']),
  _GemCategory('Shopping', Icons.shopping_bag_rounded,
      keywords: ['shop', 'store', 'market', 'mall', 'boutique', 'outlet']),
  _GemCategory('Camping', Icons.cabin_rounded,
      types: {LocationType.campground}),
  _GemCategory('Gas', Icons.local_gas_station_rounded,
      types: {LocationType.gasStation}, keywords: ['fuel', 'gas']),
  _GemCategory('Lodging', Icons.hotel_rounded,
      keywords: ['inn', 'hotel', 'motel', 'lodge', 'cabin', 'resort', 'bnb']),
  _GemCategory('Hidden Gems', Icons.diamond_rounded,
      types: {LocationType.hiddenGem}),
  _GemCategory('Events', Icons.celebration_rounded,
      keywords: ['event', 'festival', 'fair', 'concert', 'market']),
];

/// Local Gems — nearby places to eat, drink, shop, camp and explore, filtered by
/// category and sorted nearest-first. Tapping a card opens the universal
/// destination detail card (Listen / Navigate / Save).
class LocalGemsScreen extends ConsumerStatefulWidget {
  const LocalGemsScreen({super.key});
  @override
  ConsumerState<LocalGemsScreen> createState() => _LocalGemsScreenState();
}

class _LocalGemsScreenState extends ConsumerState<LocalGemsScreen> {
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gpsStatusProvider.notifier).requestAndStart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final nearby = ref.watch(nearbyLocationsProvider);
    final cat = _categories[_selected];
    final matches =
        nearby.where((n) => cat.matches(n.location)).toList(growable: false);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const RadioSubPageBar(
                  title: 'Local Gems',
                  subtitle: 'Great places to eat, drink & explore nearby.',
                ),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: RD.lg),
                    itemCount: _categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: RD.sm),
                    itemBuilder: (_, i) => RadioFilterChip(
                      label: _categories[i].label,
                      selected: i == _selected,
                      onTap: () => setState(() => _selected = i),
                    ),
                  ),
                ),
                const SizedBox(height: RD.md),
                Expanded(child: _body(nearby.isEmpty, matches)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(bool noGps, List<NearbyLocation> matches) {
    if (noGps) {
      return _empty(Icons.location_searching_rounded, 'Finding gems near you',
          'Turn on location so we can list what\'s around you.');
    }
    if (matches.isEmpty) {
      return _empty(Icons.travel_explore_rounded, 'No matches nearby',
          'Try another category — more places appear as you travel.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(RD.lg, 0, RD.lg, RD.xl),
      itemCount: matches.length,
      separatorBuilder: (_, _) => const SizedBox(height: RD.md),
      itemBuilder: (_, i) {
        final n = matches[i];
        final mi = n.distanceMeters / 1609.344;
        return LocationCard(
          title: n.location.name,
          subtitle:
              '${n.location.type.label} · ${mi.toStringAsFixed(mi < 10 ? 1 : 0)} mi',
          imageUrl:
              n.location.images.isNotEmpty ? n.location.images.first : null,
          onTap: () => showDestinationDetail(context, n.location,
              distanceMeters: n.distanceMeters),
        );
      },
    );
  }

  Widget _empty(IconData icon, String title, String body) => Center(
        child: Padding(
          padding: const EdgeInsets.all(RD.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: RD.greenDim),
              const SizedBox(height: RD.md),
              Text(title, style: RD.title),
              const SizedBox(height: RD.xs),
              Text(body, textAlign: TextAlign.center, style: RD.body),
            ],
          ),
        ),
      );
}
