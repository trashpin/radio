import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/maps/presentation/maps_screen.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/presentation/journey_map.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';

/// "THE MAP IS THE GAME BOARD" — the primary Map tab. While an adventure is
/// active, the map's whole job is to dominate: current adventure, current
/// objective, distance, mission progress (all via the existing [JourneyMap],
/// unchanged) plus one button back into the full in-mission player
/// ([MissionPlayerScreen], reached the same way starting an adventure
/// already reaches it — a pushed route, never duplicated here). With no
/// adventure active, this falls back to the existing general Explore map
/// ([MapsScreen], unchanged) — every location on it is already exactly the
/// spec's "optional discovery," nothing new needed there.
class AdventureMapScreen extends ConsumerWidget {
  const AdventureMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionState = ref.watch(activeMissionControllerProvider);
    final active = missionState.mission != null && missionState.currentStop != null;

    if (!active) return const MapsScreen();

    return Scaffold(
      backgroundColor: RD.bg,
      appBar: AppBar(
        backgroundColor: RD.bg,
        foregroundColor: RD.textPrimary,
        title: const Text('Adventure Map'),
        actions: [
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => context.push(AppRoute.more.path),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RD.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: JourneyMap()),
              const SizedBox(height: RD.md),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: RD.green, foregroundColor: RD.onGreen),
                  onPressed: () => context
                      .push(AppRoute.missionPlayer.missionPathFor(missionState.mission!.id)),
                  icon: const Icon(Icons.explore_rounded),
                  label: const Text('Continue Adventure',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
