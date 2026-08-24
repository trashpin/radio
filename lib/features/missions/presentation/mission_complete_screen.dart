import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "MISSION COMPLETE" (spec Phase 6/9) — the summary shown once the final
/// stop's discovery is unlocked. Reads whatever [ActiveMissionController]
/// already has in memory (mission, xp, completed stops) rather than
/// re-fetching — this screen is only ever reached right after completion.
class MissionCompleteScreen extends ConsumerWidget {
  const MissionCompleteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeMissionControllerProvider);
    final mission = state.mission;

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(RD.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events_rounded, color: RD.green, size: 84),
                const SizedBox(height: RD.lg),
                Text('MISSION COMPLETE', style: RD.tagline.copyWith(fontSize: 14, letterSpacing: 4)),
                const SizedBox(height: RD.sm),
                Text(mission?.title ?? 'Adventure Complete',
                    style: RD.wordmark.copyWith(fontSize: 24),
                    textAlign: TextAlign.center),
                const SizedBox(height: RD.xl),
                GlassPanel(
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _stat('${state.xp}', 'XP earned'),
                      _stat('${state.completedStopIds.length}', 'Stops discovered'),
                    ]),
                    if ((mission?.completionBadge ?? '').isNotEmpty) ...[
                      const SizedBox(height: RD.md),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: RD.md, vertical: RD.sm),
                        decoration: BoxDecoration(
                          color: RD.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(RD.rPill),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.military_tech_rounded, color: RD.green, size: 18),
                          const SizedBox(width: RD.xs),
                          Text(mission!.completionBadge!, style: RD.caption.copyWith(color: RD.green)),
                        ]),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: RD.xxl),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: RD.green, foregroundColor: RD.onGreen),
                    onPressed: () => context.go(AppRoute.missionsHome.path),
                    child: const Text('Back to Adventures', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value, style: RD.wordmark.copyWith(fontSize: 28)),
        Text(label, style: RD.caption),
      ]);
}
