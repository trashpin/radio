import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/models/discovery_area.dart';
import 'package:explorer_os_mobile/features/discover_area/models/nearby_attractions.dart';
import 'package:explorer_os_mobile/features/discover_area/providers/area_attractions_provider.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart' show formatDistance;
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/discovery/nearby_narration_controller.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// Attractions near the current area — museums, parks, historic sites,
/// trails, scenic overlooks, hidden gems — all pulled straight from Master
/// Locations (no separate content system). Tapping one narrates it through
/// [NearbyNarrationController.narrateLocation] — the same mechanism "What's
/// Near Me" already uses for any Master Location — then returns to the radio.
class AreaAttractionsScreen extends ConsumerWidget {
  const AreaAttractionsScreen({super.key, required this.area});
  final DiscoveryArea area;

  void _pick(BuildContext context, WidgetRef ref, AttractionMatch m) {
    ref.read(nearbyNarrationControllerProvider.notifier).narrateLocation(m.location);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attractions = ref.watch(areaAttractionsProvider(area));
    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            RadioSubPageBar(title: 'Attractions', subtitle: area.name),
            Expanded(
              child: attractions.isEmpty
                  ? _empty()
                  : ListView.separated(
                      padding: const EdgeInsets.all(RD.lg),
                      itemCount: attractions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: RD.sm),
                      itemBuilder: (context, i) {
                        final m = attractions[i];
                        return GlassPanel(
                          onTap: () => _pick(context, ref, m),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.location.name, style: RD.cardTitle),
                                    const SizedBox(height: 2),
                                    Text(m.location.type.label,
                                        style: RD.body.copyWith(fontSize: 12)),
                                  ],
                                ),
                              ),
                              GlassChip(
                                child: Text(formatDistance(m.distanceMeters),
                                    style: RD.badge.copyWith(color: RD.textPrimary)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.attractions_rounded, size: 56, color: RD.textSecondary),
            const SizedBox(height: RD.lg),
            Text('No attractions mapped near ${area.name} yet.',
                textAlign: TextAlign.center, style: RD.title.copyWith(fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
