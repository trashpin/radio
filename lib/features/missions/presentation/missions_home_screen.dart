import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "OPEN APP -> SELECT ADVENTURE" (spec Phase 6/7) — the published-adventure
/// list. Deliberately not a bottom-nav tab yet (Phase 7's full EXPLORE/
/// MISSIONS/DISCOVER/MY JOURNEY navigation is explicitly out of scope for
/// this pass) — reached via a direct link for now.
class MissionsHomeScreen extends ConsumerWidget {
  const MissionsHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionsAsync = ref.watch(publishedMissionsProvider);
    return Scaffold(
      backgroundColor: RD.bg,
      appBar: AppBar(
        backgroundColor: RD.bg,
        foregroundColor: RD.textPrimary,
        title: const Text('Marion County Adventures'),
      ),
      body: SafeArea(
        child: missionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: RD.green)),
          error: (e, _) => Center(
            child: Text('Could not load adventures.', style: RD.body),
          ),
          data: (missions) => missions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(RD.xl),
                    child: Text(
                      'No adventures are published yet. Check back soon.',
                      style: RD.body,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(RD.lg),
                  itemCount: missions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: RD.md),
                  itemBuilder: (context, i) => _MissionCard(mission: missions[i]),
                ),
        ),
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      onTap: () => context.push(AppRoute.missionPlayer.missionPathFor(mission.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(mission.title, style: RD.title),
            ),
            const Icon(Icons.chevron_right_rounded, color: RD.textSecondary),
          ]),
          if ((mission.description ?? '').isNotEmpty) ...[
            const SizedBox(height: RD.xs),
            Text(mission.description!, style: RD.body, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: RD.sm),
          Wrap(spacing: RD.sm, runSpacing: RD.xs, children: [
            if ((mission.category ?? '').isNotEmpty) _chip(mission.category!),
            if ((mission.difficulty ?? '').isNotEmpty) _chip(mission.difficulty!),
            if (mission.estimatedDurationMinutes != null)
              _chip('${mission.estimatedDurationMinutes} min'),
          ]),
        ],
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: RD.sm, vertical: 4),
        decoration: BoxDecoration(
          color: RD.panelAlt,
          borderRadius: BorderRadius.circular(RD.rPill),
        ),
        child: Text(label, style: RD.caption),
      );
}
