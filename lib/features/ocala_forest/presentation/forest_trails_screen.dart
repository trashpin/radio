import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/discover_area/models/tour_mode.dart';
import 'package:explorer_os_mobile/features/ocala_forest/controllers/forest_experience_controller.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_trail.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/forest_trail_detail_screen.dart';
import 'package:explorer_os_mobile/features/ocala_forest/presentation/widgets/forest_audio_bar.dart';
import 'package:explorer_os_mobile/features/ocala_forest/providers/ocala_forest_providers.dart';
import 'package:explorer_os_mobile/features/ocala_forest/services/forest_playback.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// TRAILS — two independent sections:
///
/// 1. "Official Trails": the real, official USFS trail records imported by
///    the ocala-trails-import edge function (migration 0050) — name,
///    official number, length/type/managing org when the source provided
///    them, source attribution. Selecting one (VIEW TRAIL) opens the
///    dedicated trail page (ForestTrailDetailScreen) — trail info, the
///    actual trail map, and the ElevenLabs Trail Audio Tour.
/// 2. The existing trail-stop checklist from v2 (`experienceType ==
///    'trail_stop'` forest_locations) — unchanged; GPS arrival narration is
///    already live via the shared `ForestExperienceController`.
class ForestTrailsScreen extends ConsumerStatefulWidget {
  const ForestTrailsScreen({super.key});

  @override
  ConsumerState<ForestTrailsScreen> createState() => _ForestTrailsScreenState();
}

class _ForestTrailsScreenState extends ConsumerState<ForestTrailsScreen> {
  TourMode _mode = TourMode.walking;

  @override
  Widget build(BuildContext context) {
    final trailsAsync = ref.watch(forestTrailsProvider);
    final locationsAsync = ref.watch(forestLocationsProvider);
    final stops = (locationsAsync.value ?? const <ForestLocation>[])
        .where((l) => l.isTrailStop && l.active)
        .toList();
    final experience = ref.watch(forestExperienceControllerProvider);
    final trails = [...trailsAsync.value ?? const <ForestTrail>[]]
      ..sort((a, b) => a.trailNo.compareTo(b.trailNo));

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Column(
          children: [
            const RadioSubPageBar(title: 'Trails', subtitle: 'Ocala National Forest'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(RD.lg),
                children: [
                  Text('Official Trails', style: RD.sectionLabel),
                  const SizedBox(height: RD.xs),
                  Text(
                    'Real trail records from the U.S. Forest Service — nothing '
                    'here is estimated or invented.',
                    style: RD.caption.copyWith(color: RD.textSecondary),
                  ),
                  const SizedBox(height: RD.sm),
                  if (trailsAsync.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: RD.lg),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (trails.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: RD.lg),
                      child: Text(
                        'No official trail records have been imported yet.',
                        style: RD.body.copyWith(color: RD.textSecondary),
                      ),
                    )
                  else
                    for (final trail in trails) ...[
                      _OfficialTrailCard(trail: trail),
                      const SizedBox(height: RD.sm),
                    ],
                  const SizedBox(height: RD.lg),
                  const Divider(color: RD.textFaint, height: 1),
                  const SizedBox(height: RD.lg),
                  Text('Trail Stops', style: RD.sectionLabel),
                  const SizedBox(height: RD.sm),
                  const ForestAudioBar(),
                  const SizedBox(height: RD.sm),
                  Row(
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
                  const SizedBox(height: RD.sm),
                  if (stops.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: RD.lg),
                      child: Text(
                        'No trail stops have been mapped in Ocala National '
                        'Forest yet.',
                        style: RD.body.copyWith(color: RD.textSecondary),
                      ),
                    )
                  else
                    for (final stop in stops) ...[
                      GlassPanel(
                        onTap: () => playForestLocation(ref, stop),
                        child: Row(
                          children: [
                            Icon(
                              experience.visitedIds.contains(stop.id)
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked,
                              color: experience.visitedIds.contains(stop.id)
                                  ? RD.green
                                  : RD.textSecondary,
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
                      ),
                      const SizedBox(height: RD.sm),
                    ],
                  const SizedBox(height: RD.sm),
                  Text(
                    _mode == TourMode.walking
                        ? 'Walk near a trail stop and it narrates automatically.'
                        : 'Drive near a trail stop and it narrates automatically.',
                    textAlign: TextAlign.center,
                    style: RD.caption.copyWith(color: RD.textSecondary),
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

class _OfficialTrailCard extends StatelessWidget {
  const _OfficialTrailCard({required this.trail});
  final ForestTrail trail;

  @override
  Widget build(BuildContext context) {
    final title = (trail.trailName?.trim().isNotEmpty ?? false)
        ? trail.trailName!.trim()
        : 'Trail ${trail.trailNo}';
    final details = <String>[
      'No. ${trail.trailNo}',
      if (trail.lengthMiles != null) '${trail.lengthMiles!.toStringAsFixed(1)} mi',
      if (trail.trailType != null && trail.trailType!.trim().isNotEmpty) trail.trailType!,
      if (trail.managingOrg != null && trail.managingOrg!.trim().isNotEmpty)
        'Managing org ${trail.managingOrg}',
    ];
    return GlassPanel(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ForestTrailDetailScreen(trail: trail))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_rounded, color: RD.textFaint),
              const SizedBox(width: RD.sm),
              Expanded(
                child: Text(title,
                    style: RD.cardTitle.copyWith(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: RD.xs),
          Text(details.join(' · '), style: RD.caption.copyWith(color: RD.textSecondary)),
          const SizedBox(height: RD.xs),
          Text(
            'Source: ${trail.source ?? 'U.S. Forest Service'}',
            style: RD.caption.copyWith(color: RD.textFaint),
          ),
          const SizedBox(height: RD.xs),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('VIEW TRAIL', style: RD.caption.copyWith(color: RD.green)),
                const Icon(Icons.chevron_right_rounded, color: RD.green, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
