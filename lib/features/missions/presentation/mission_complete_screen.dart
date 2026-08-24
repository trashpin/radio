import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/missions/controllers/active_mission_controller.dart';
import 'package:explorer_os_mobile/features/missions/presentation/widgets/character_video_hero.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "MISSION COMPLETE" (spec Phase 6/9) — the summary shown once the final
/// stop's discovery (and any final puzzle) is unlocked. Reads whatever
/// [ActiveMissionController] already has in memory (mission, xp, completed
/// stops) rather than re-fetching — this screen is only ever reached right
/// after completion.
class MissionCompleteScreen extends ConsumerWidget {
  const MissionCompleteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activeMissionControllerProvider);
    final mission = state.mission;

    return Scaffold(
      backgroundColor: RD.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(RD.xl),
          children: [
            const SizedBox(height: RD.lg),
            const Icon(Icons.emoji_events_rounded, color: RD.green, size: 84),
            const SizedBox(height: RD.lg),
            Text('YOU SOLVED IT', style: RD.tagline.copyWith(fontSize: 14, letterSpacing: 4),
                textAlign: TextAlign.center),
            const SizedBox(height: RD.sm),
            Text(mission?.title ?? 'Adventure Complete',
                style: RD.wordmark.copyWith(fontSize: 24),
                textAlign: TextAlign.center),
            const SizedBox(height: RD.xl),

            // The Final Reveal — how the clues connected (spec: "the final
            // reveal should connect something the player saw earlier with
            // something they eventually learn"). Re-showing the mission's
            // own hero image here is the literal payoff of that rule: it's
            // the SAME artwork the player glanced at before knowing it
            // mattered — the "I saw that earlier" moment made structural,
            // not just described in the reveal text.
            if (mission?.hasHeroImage ?? false) ...[
              ClipRRect(
                borderRadius: RD.brLg,
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Image.network(mission!.heroImageUrl!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: RD.lg),
            ],
            if (mission?.hasFinalRevealVideo ?? false) ...[
              CharacterVideoHero(videoUrl: mission!.finalRevealVideoUrl!),
              const SizedBox(height: RD.lg),
            ] else if ((mission?.finalRevealText ?? '').isNotEmpty) ...[
              GlassPanel(
                child: Text(mission!.finalRevealText!,
                    style: RD.body.copyWith(fontSize: 15, color: RD.textPrimary, height: 1.5)),
              ),
              const SizedBox(height: RD.lg),
            ],

            // "THE REAL HISTORY" — deliberately separate from the dramatic
            // reveal above: what's verified, what source supports it, what
            // was fictionalized, and why it matters (spec: never present
            // invented dialogue as an authentic historical quote).
            if ((mission?.realHistoryText ?? '').isNotEmpty) ...[
              GlassPanel(
                color: RD.panelAlt,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.fact_check_outlined, color: RD.amber, size: 18),
                      const SizedBox(width: RD.xs),
                      Text('THE REAL HISTORY', style: RD.sectionLabel.copyWith(color: RD.amber)),
                    ]),
                    const SizedBox(height: RD.sm),
                    Text(mission!.realHistoryText!,
                        style: RD.body.copyWith(fontSize: 14, color: RD.textPrimary, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: RD.lg),
            ],

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
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: RD.green, foregroundColor: RD.onGreen),
                onPressed: () => context.go(AppRoute.missionsHome.path),
                child: const Text('Back to Adventures', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value, style: RD.wordmark.copyWith(fontSize: 28)),
        Text(label, style: RD.caption),
      ]);
}
