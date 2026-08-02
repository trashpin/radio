import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/controllers/area_tour_controller.dart';
import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/discover_area/models/nearby_attractions.dart';
import 'package:explorer_os_mobile/features/discover_area/models/tour_mode.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart' show formatDistance;
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// Driving/Walking Tour — GPS-guided narration that fires automatically as
/// the traveler nears each stop (see [AreaTourController]), rather than
/// something the traveler taps through manually. This screen is mostly a
/// live status view: which stops have played, which are still ahead.
class AreaTourScreen extends ConsumerStatefulWidget {
  const AreaTourScreen({super.key, required this.area, required this.mode});
  final DiscoveryArea area;
  final TourMode mode;

  @override
  ConsumerState<AreaTourScreen> createState() => _AreaTourScreenState();
}

class _AreaTourScreenState extends ConsumerState<AreaTourScreen> {
  bool _started = false;

  // Captured in initState so dispose() never touches `ref` (unsafe after
  // unmount) — a lazy `late` field would initialize during dispose.
  late final AreaTourController _tour;

  @override
  void initState() {
    super.initState();
    _tour = ref.read(areaTourControllerProvider.notifier);
  }

  @override
  void dispose() {
    _tour.stop();
    super.dispose();
  }

  void _maybeStart(List<AttractionMatch> stops) {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _tour.start(stops, widget.mode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(masterLocationsProvider).value ?? const [];
    final stops = nearbyAttractions(
      all,
      widget.area.location,
      radiusMeters: widget.mode.stopSearchRadiusMeters,
    );
    final tour = ref.watch(areaTourControllerProvider);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(title: widget.mode.label, subtitle: widget.area.name),
            Expanded(
              child: stops.isEmpty ? _unavailable() : _body(stops, tour),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unavailable() {
    final isWalking = widget.mode == TourMode.walking;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWalking ? Icons.directions_walk_rounded : Icons.directions_car_rounded,
              size: 56,
              color: RD.textSecondary,
            ),
            const SizedBox(height: RD.lg),
            Text('${widget.mode.label} not available here yet',
                textAlign: TextAlign.center, style: RD.title.copyWith(fontSize: 20)),
            const SizedBox(height: RD.sm),
            Text(
              isWalking
                  ? 'No attractions are close enough to walk between for '
                      '${widget.area.name}. Try the Driving Tour instead.'
                  : 'No attractions have been mapped near ${widget.area.name} yet.',
              textAlign: TextAlign.center,
              style: RD.body,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(List<AttractionMatch> stops, AreaTourState tour) {
    _maybeStart(stops);
    final visited = tour.stops.isEmpty ? 0 : tour.visitedCount;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RD.lg, vertical: RD.sm),
          child: Row(
            children: [
              Icon(Icons.gps_fixed_rounded, size: 16, color: RD.green),
              const SizedBox(width: RD.xs),
              Expanded(
                child: Text(
                  '$visited of ${stops.length} stops narrated — keep '
                  '${widget.mode == TourMode.walking ? "walking" : "driving"}',
                  style: RD.body.copyWith(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(RD.lg),
            itemCount: stops.length,
            separatorBuilder: (_, __) => const SizedBox(height: RD.sm),
            itemBuilder: (context, i) {
              final stop = stops[i];
              final isVisited = tour.visitedIds.contains(stop.location.id);
              return GlassPanel(
                child: Row(
                  children: [
                    Icon(
                      isVisited ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      color: isVisited ? RD.green : RD.textSecondary,
                    ),
                    const SizedBox(width: RD.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(stop.location.name, style: RD.cardTitle),
                          Text(stop.location.type.label,
                              style: RD.body.copyWith(fontSize: 12)),
                        ],
                      ),
                    ),
                    GlassChip(
                      child: Text(formatDistance(stop.distanceMeters),
                          style: RD.badge.copyWith(color: RD.textPrimary)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(RD.lg),
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('End Tour'),
          ),
        ),
      ],
    );
  }
}
