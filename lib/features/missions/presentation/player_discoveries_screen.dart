import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/missions/data/player_discoveries_provider.dart';
import 'package:explorer_os_mobile/features/missions/models/mission_fact.dart';
import 'package:explorer_os_mobile/features/missions/models/old_world.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "MY DISCOVERIES" — the player's personal Explorer journal: every
/// adventure completed or in progress, every character/story chapter
/// unlocked, and every fact learned along the way. Deliberately built
/// entirely from data the game already durably tracks
/// ([playerDiscoveriesProvider], sourced from `mission_progress`) — no new
/// collection/reward system invented. Sections the spec asks for with no
/// backing per-player record today (Wildlife, Plants, Artifacts,
/// Photographs, treasure-hunt "found" tracking) are intentionally absent
/// rather than faked; see the shipped feature report for that gap.
class PlayerDiscoveriesScreen extends ConsumerWidget {
  const PlayerDiscoveriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playerDiscoveriesProvider);
    return Scaffold(
      backgroundColor: RD.bg,
      appBar: AppBar(
        backgroundColor: RD.bg,
        foregroundColor: RD.textPrimary,
        title: const Text('My Discoveries'),
        actions: [
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => context.push(AppRoute.more.path),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: RD.green)),
          error: (e, _) =>
              Center(child: Text('Could not load your discoveries.', style: RD.body)),
          data: (d) => d.isEmpty
              ? const _EmptyJournal()
              : ListView(
                  padding: const EdgeInsets.all(RD.lg),
                  children: [
                    _XpBanner(totalXp: d.totalXp, completedCount: d.completed.length),
                    if (d.inProgress.isNotEmpty) ...[
                      const SizedBox(height: RD.lg),
                      _SectionLabel('IN PROGRESS'),
                      for (final s in d.inProgress) _MissionRow(summary: s),
                    ],
                    if (d.completed.isNotEmpty) ...[
                      const SizedBox(height: RD.lg),
                      _SectionLabel('COMPLETED ADVENTURES'),
                      for (final s in d.completed) _MissionRow(summary: s),
                    ],
                    if (d.unlockedOldWorlds.isNotEmpty) ...[
                      const SizedBox(height: RD.lg),
                      _SectionLabel('STORIES & CHARACTERS DISCOVERED'),
                      for (final w in d.unlockedOldWorlds) _OldWorldRow(world: w),
                    ],
                    if (d.learnedFacts.isNotEmpty) ...[
                      const SizedBox(height: RD.lg),
                      _SectionLabel('WHAT YOU LEARNED'),
                      for (final f in d.learnedFacts) _FactRow(fact: f),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RD.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_outlined, size: 48, color: RD.textSecondary),
            const SizedBox(height: RD.md),
            Text(
              'Your journal is empty. Start an adventure to begin discovering '
              'Marion County.',
              style: RD.body,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _XpBanner extends StatelessWidget {
  const _XpBanner({required this.totalXp, required this.completedCount});
  final int totalXp;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TOTAL XP', style: RD.sectionLabel.copyWith(color: RD.amber)),
              Text('$totalXp', style: RD.wordmark.copyWith(fontSize: 28, color: Colors.white)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('ADVENTURES COMPLETED', style: RD.sectionLabel.copyWith(color: RD.green)),
            Text('$completedCount', style: RD.wordmark.copyWith(fontSize: 28, color: Colors.white)),
          ],
        ),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RD.sm),
      child: Text(text, style: RD.sectionLabel.copyWith(color: RD.amber, letterSpacing: 1.5)),
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({required this.summary});
  final MissionDiscoverySummary summary;

  @override
  Widget build(BuildContext context) {
    final mission = summary.mission;
    final progress = summary.progress;
    return Padding(
      padding: const EdgeInsets.only(bottom: RD.sm),
      child: GlassPanel(
        onTap: () => context.push(AppRoute.missionIntro.missionIntroPathFor(mission.id)),
        child: Row(children: [
          ClipRRect(
            borderRadius: RD.brMd,
            child: SizedBox(
              width: 52,
              height: 52,
              child: mission.hasHeroImage
                  ? Image.network(mission.heroImageUrl!, fit: BoxFit.cover)
                  : Container(
                      color: RD.panelAlt,
                      child: const Icon(Icons.auto_stories_rounded, color: RD.textSecondary),
                    ),
            ),
          ),
          const SizedBox(width: RD.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mission.title, style: RD.cardTitle.copyWith(color: Colors.white)),
                Text(
                  progress.isCompleted
                      ? 'Completed · ${progress.xp} XP'
                      : 'In progress · ${progress.xp} XP so far',
                  style: RD.caption.copyWith(color: RD.textSecondary),
                ),
              ],
            ),
          ),
          Icon(
            progress.isCompleted ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
            color: progress.isCompleted ? RD.green : RD.textSecondary,
          ),
        ]),
      ),
    );
  }
}

class _OldWorldRow extends StatelessWidget {
  const _OldWorldRow({required this.world});
  final OldWorld world;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RD.sm),
      child: GlassPanel(
        child: Row(children: [
          ClipRRect(
            borderRadius: RD.brMd,
            child: SizedBox(
              width: 48,
              height: 48,
              child: (world.heroImageUrl ?? '').isNotEmpty
                  ? Image.network(world.heroImageUrl!, fit: BoxFit.cover)
                  : Container(
                      color: RD.panelAlt,
                      child: const Icon(Icons.theater_comedy_rounded, color: RD.textSecondary),
                    ),
            ),
          ),
          const SizedBox(width: RD.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(world.title, style: RD.cardTitle.copyWith(color: Colors.white)),
                if ((world.historicalPeriod ?? '').isNotEmpty)
                  Text(world.historicalPeriod!, style: RD.caption.copyWith(color: RD.textSecondary)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact});
  final MissionFact fact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: RD.sm),
      child: GlassPanel(
        child: Row(children: [
          const Icon(Icons.lightbulb_rounded, color: RD.amber, size: 20),
          const SizedBox(width: RD.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fact.label, style: RD.caption.copyWith(color: RD.textSecondary)),
                Text(fact.value, style: RD.body.copyWith(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
