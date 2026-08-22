import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/models/tour_mode.dart';
import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_experience_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';
import 'package:explorer_os_mobile/features/ocala_forest/services/forest_playback.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// TRAILS — trail-stop forest locations (`experienceType == 'trail_stop'`).
/// Reuses `TourMode` as-is (`lib/features/discover_area/models/tour_mode.dart`)
/// for the walking/driving trigger-radius distinction; the actual GPS
/// arrival narration is already live (the shared
/// `ForestExperienceController` narrates ANY forest location on arrival,
/// started by the hub screen) — this screen is a live checklist mirroring
/// `AreaTourScreen`'s layout, not a second trigger engine.
class ForestTrailsScreen extends ConsumerStatefulWidget {
  const ForestTrailsScreen({super.key});

  @override
  ConsumerState<ForestTrailsScreen> createState() => _ForestTrailsScreenState();
}

class _ForestTrailsScreenState extends ConsumerState<ForestTrailsScreen> {
  TourMode _mode = TourMode.walking;

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(forestLocationsProvider);
    final stops = (locationsAsync.value ?? const <ForestLocation>[])
        .where((l) => l.isTrailStop && l.active)
        .toList();
    final experience = ref.watch(forestExperienceControllerProvider);

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(title: 'Trails', subtitle: 'Ocala National Forest'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RD.lg),
              child: Row(
                children: [
                  for (final mode in TourMode.values) ...[
                    Expanded(
                      child: RadioFilterChip(
                        label: mode.label,
                        selected: _mode == mode,
                        onTap: () => setState(() => _mode = mode),
                      ),
                    ),
                    if (mode != TourMode.values.last) const SizedBox(width: RD.sm),
                  ],
                ],
              ),
            ),
            const SizedBox(height: RD.sm),
            Expanded(
              child: stops.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(RD.xl),
                        child: Text(
                          'No trail stops have been mapped in Ocala National '
                          'Forest yet.',
                          textAlign: TextAlign.center,
                          style: RD.body.copyWith(color: RD.textSecondary),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(RD.lg),
                      itemCount: stops.length,
                      separatorBuilder: (_, _) => const SizedBox(height: RD.sm),
                      itemBuilder: (context, i) {
                        final stop = stops[i];
                        final visited = experience.visitedIds.contains(stop.id);
                        return GlassPanel(
                          onTap: () => playForestLocation(ref, stop),
                          child: Row(
                            children: [
                              Icon(
                                visited
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked,
                                color: visited ? RD.green : RD.textSecondary,
                              ),
                              const SizedBox(width: RD.sm),
                              Expanded(
                                child: Text(stop.name,
                                    style: RD.cardTitle.copyWith(color: Colors.white)),
                              ),
                              const Icon(Icons.play_circle_outline_rounded,
                                  color: RD.textFaint),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(RD.lg),
              child: Text(
                _mode == TourMode.walking
                    ? 'Walk near a trail stop and it narrates automatically.'
                    : 'Drive near a trail stop and it narrates automatically.',
                textAlign: TextAlign.center,
                style: RD.caption.copyWith(color: RD.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
