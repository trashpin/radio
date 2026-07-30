import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/gps/providers/gps_status_provider.dart';
import 'package:explorer_os_mobile/features/location_intelligence/data/location_content_repository.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';
import 'package:explorer_os_mobile/features/locations/presentation/destination_detail_card.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/profile/data/user_profile_repository.dart';
import 'package:explorer_os_mobile/features/radio/controllers/radio_engine_controller.dart';
import 'package:explorer_os_mobile/features/weather/weather_service.dart';

/// The new Home / Explore landing — a professional travel-companion feed that
/// answers "What should I discover next?" instead of a map full of pins.
class ExploreHomeScreen extends ConsumerStatefulWidget {
  const ExploreHomeScreen({super.key});
  @override
  ConsumerState<ExploreHomeScreen> createState() => _ExploreHomeScreenState();
}

class _P {
  static const bg = Color(0xFF0E1512);
  static const card = Color(0xFF1B2620);
  static const green = Color(0xFF2E9E6B);
  static const gold = Color(0xFFF2B33D);
  static const text = Color(0xFFF3F6F2);
  static const dim = Color(0xFF9CA8A1);
}

/// A named group of destination types for the Explore feed.
class _Group {
  const _Group(this.title, this.types);
  final String title;
  final Set<LocationType> types;
}

const _groups = <_Group>[
  _Group('Nature & Parks', {
    LocationType.statePark, LocationType.nationalPark, LocationType.countyPark,
    LocationType.forest, LocationType.wildlifeViewing, LocationType.scenicOverlook,
  }),
  _Group('Springs & Water', {
    LocationType.spring, LocationType.river, LocationType.lake,
    LocationType.boatRamp,
  }),
  _Group('Historic & Culture', {
    LocationType.historicSite, LocationType.historicDistrict,
    LocationType.museum,
  }),
  _Group('Trails & Camping', {
    LocationType.trail, LocationType.trailhead, LocationType.campground,
  }),
  _Group('Attractions & More', {
    LocationType.attraction, LocationType.restaurant, LocationType.hiddenGem,
    LocationType.scenicRoad, LocationType.city, LocationType.community,
  }),
];

class _ExploreHomeScreenState extends ConsumerState<ExploreHomeScreen> {
  WeatherData? _weather;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gpsStatusProvider.notifier).requestAndStart().catchError(
          (_) => ref.read(gpsStatusProvider));
      _loadWeather();
    });
  }

  Future<void> _loadWeather() async {
    final c = ref.read(mapCenterProvider);
    final g = ref.read(gpsStatusProvider);
    final lat = c?.latitude ?? g.latitude;
    final lng = c?.longitude ?? g.longitude;
    if (lat == null || lng == null) return;
    final w = await ref.read(weatherClientProvider).fetch(lat, lng);
    if (mounted && w != null) setState(() => _weather = w);
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final ctx = ref.watch(locationContextProvider);
    final profile = ref.watch(currentUserProfileProvider).value;
    final name = (profile?.firstName?.trim().isNotEmpty ?? false)
        ? profile!.firstName!.trim()
        : 'Explorer';
    final nowPlaying =
        ref.watch(radioEngineControllerProvider).current?.segment.title;
    final nearby = ref.watch(nearbyLocationsProvider);
    final all = ref.watch(masterLocationsProvider).value ?? const [];
    final center = ref.watch(mapCenterProvider);

    // Weather may arrive after first build; reload lazily once we have a fix.
    if (_weather == null && center != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadWeather());
    }

    return Scaffold(
      backgroundColor: _P.bg,
      body: ListView(
        padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 16, bottom: 120),
        children: [
          _header(name, ctx.county, ctx.state),
          const SizedBox(height: 16),
          _nowPlaying(nowPlaying),
          const SizedBox(height: 22),
          _quickActions(),
          const SizedBox(height: 22),
          if (nearby.isNotEmpty)
            _highlightSection('Nearby Highlights',
                nearby.take(10).map((n) => (n.location, n.distanceMeters)).toList()),
          for (final g in _groups)
            _groupSection(g, all, center),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  Widget _header(String name, String? county, String? state) {
    final place = [county == null ? null : '$county County', state]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final wx = _weather;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$_greeting, $name',
              style: const TextStyle(
                  color: _P.text, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.place_rounded, size: 16, color: _P.green),
            const SizedBox(width: 6),
            Text(place.isEmpty ? 'Finding your location…' : place,
                style: const TextStyle(color: _P.dim, fontSize: 14)),
            if (wx?.temperatureF != null || wx?.highF != null) ...[
              const SizedBox(width: 14),
              const Icon(Icons.wb_sunny_rounded, size: 16, color: _P.gold),
              const SizedBox(width: 6),
              Text(
                  '${(wx!.temperatureF ?? wx.highF)!.round()}° · ${wx.condition}',
                  style: const TextStyle(color: _P.dim, fontSize: 14)),
            ],
          ]),
        ],
      ),
    );
  }

  // ── Now playing / continue ─────────────────────────────────────────────
  Widget _nowPlaying(String? title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: _P.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.go(AppRoute.radio.path),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                    color: _P.green.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.podcasts_rounded, color: _P.green),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ExplorerOS Radio',
                        style: TextStyle(
                            color: _P.dim,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                        (title ?? '').trim().isNotEmpty
                            ? title!
                            : 'Continue Exploring',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _P.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const Icon(Icons.play_circle_fill_rounded,
                  color: _P.green, size: 34),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Quick actions ────────────────────────────────────────────────────────
  Widget _quickActions() {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.podcasts_rounded, 'Radio', () => context.go(AppRoute.radio.path)),
      (Icons.near_me_rounded, 'Nearby', () => context.push(AppRoute.aroundMe.path)),
      (Icons.map_rounded, 'Map', () => context.go(AppRoute.map.path)),
      (Icons.menu_book_rounded, 'Stories', () => context.go(AppRoute.stories.path)),
      (Icons.smart_toy_rounded, 'AI Ranger',
          () => context.push(AppRoute.aiRanger.path)),
    ];
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final (icon, label, tap) = actions[i];
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: tap,
            child: Container(
              width: 78,
              decoration: BoxDecoration(
                  color: _P.card, borderRadius: BorderRadius.circular(18)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: _P.gold, size: 26),
                  const SizedBox(height: 8),
                  Text(label,
                      style: const TextStyle(color: _P.text, fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────
  Widget _groupSection(
      _Group g, List<MasterLocation> all, dynamic center) {
    final engine = ref.read(locationEngineProvider);
    List<(MasterLocation, double?)> items;
    if (center != null) {
      items = engine
          .nearby(center.latitude, center.longitude, all,
              maxMiles: 60, types: g.types)
          .take(10)
          .map((n) => (n.location, n.distanceMeters as double?))
          .toList();
    } else {
      items = [
        for (final l in all)
          if (l.active && !l.hidden && g.types.contains(l.type))
            (l, null as double?),
      ].take(10).toList();
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return _highlightSection(g.title, items);
  }

  Widget _highlightSection(
      String title, List<(MasterLocation, double?)> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(title,
              style: const TextStyle(
                  color: _P.text, fontSize: 19, fontWeight: FontWeight.w800)),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final (loc, dist) = items[i];
              return _DestinationCard(location: loc, distanceMeters: dist);
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.location, this.distanceMeters});
  final MasterLocation location;
  final double? distanceMeters;

  @override
  Widget build(BuildContext context) {
    final hero = location.images.isNotEmpty ? location.images.first : null;
    final miles = distanceMeters == null
        ? null
        : (distanceMeters! / 1609.344);
    return SizedBox(
      width: 260,
      child: Material(
        color: _P.card,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showDestinationDetail(context, location,
              distanceMeters: distanceMeters),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 130,
                width: double.infinity,
                child: hero != null
                    ? Image.network(hero, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _fallback())
                    : _fallback(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(location.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _P.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      [
                        location.type.label,
                        if (miles != null)
                          '${miles < 10 ? miles.toStringAsFixed(1) : miles.round()} mi',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _P.dim, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        color: const Color(0xFF223028),
        child: const Center(
            child: Icon(Icons.image_rounded, color: _P.green, size: 40)),
      );
}
