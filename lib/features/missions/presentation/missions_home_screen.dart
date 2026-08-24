import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/features/missions/data/mission_repository.dart';
import 'package:explorer_os_mobile/features/missions/models/mission.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';
import 'package:explorer_os_mobile/features/radio/widgets/radio_widgets.dart';

/// "OPEN APP -> SELECT ADVENTURE" — the Adventures page as a storefront of
/// visual Adventure Cards, not a text listing. Its job is to make the
/// player WANT to pick one, never to explain the whole journey — see
/// [_AdventureCard]'s own doc comment for the no-spoiler rules that govern
/// what a card is allowed to show.
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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(RD.lg, RD.sm, RD.lg, RD.lg),
                  children: [
                    Text(
                      'Every detail might matter. Listen closely.',
                      style: RD.caption.copyWith(color: RD.textSecondary, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: RD.md),
                    for (final m in missions) ...[
                      _AdventureCard(mission: m),
                      const SizedBox(height: RD.lg),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// The visual storefront card for one adventure.
///
/// STRICT NO-SPOILER RULE (spec: "the Adventures page should make the
/// player ask 'what is this about?', not answer it"): this widget only
/// ever reads [Mission.heroImageUrl] (mystery artwork, never a destination
/// photo), [Mission.storyHook] (a curiosity-only teaser), [Mission.title],
/// [Mission.category]/[Mission.difficulty]/[Mission.estimatedDurationMinutes].
/// It never reads mission stops, locations, or the route — it has no way to
/// leak them because it never fetches them.
class _AdventureCard extends StatelessWidget {
  const _AdventureCard({required this.mission});
  final Mission mission;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: EdgeInsets.zero,
      radius: RD.rLg,
      onTap: () => context.push(AppRoute.missionIntro.missionIntroPathFor(mission.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(RD.rLg)),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: mission.hasHeroImage
                  ? Image.network(
                      mission.heroImageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _HeroPlaceholder(),
                      loadingBuilder: (c, child, p) => p == null
                          ? child
                          : const _HeroPlaceholder(loading: true),
                    )
                  : const _HeroPlaceholder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(RD.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mission.title.toUpperCase(),
                    style: RD.wordmark.copyWith(fontSize: 20, letterSpacing: 0.5)),
                if ((mission.storyHook ?? mission.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: RD.sm),
                  Text(
                    '"${(mission.storyHook ?? mission.description)!.trim()}"',
                    style: RD.body.copyWith(
                        fontSize: 14, height: 1.4, color: RD.textPrimary, fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: RD.md),
                Wrap(spacing: RD.sm, runSpacing: RD.xs, children: [
                  if ((mission.category ?? '').isNotEmpty)
                    _chip(Icons.auto_awesome_rounded, mission.category!),
                  if ((mission.difficulty ?? '').isNotEmpty)
                    _chip(Icons.psychology_alt_rounded, mission.difficulty!),
                  if (mission.estimatedDurationMinutes != null)
                    _chip(Icons.schedule_rounded, '${mission.estimatedDurationMinutes} min'),
                ]),
                const SizedBox(height: RD.lg),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: RD.green, foregroundColor: RD.onGreen),
                    onPressed: () =>
                        context.push(AppRoute.missionIntro.missionIntroPathFor(mission.id)),
                    child: const Text('DISCOVER THE ADVENTURE',
                        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: RD.sm, vertical: 5),
        decoration: BoxDecoration(
          color: RD.panelAlt,
          borderRadius: BorderRadius.circular(RD.rPill),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: RD.green),
          const SizedBox(width: 4),
          Text(label, style: RD.caption),
        ]),
      );
}

/// Shown when a mission has no [Mission.heroImageUrl] yet — deliberately
/// NOT a destination photo (spec: never auto-use a location's image unless
/// specifically configured). A generic mystery motif, not a broken-image
/// icon or an empty gray box, so an unconfigured card still feels like part
/// of the game rather than a missing asset.
class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder({this.loading = false});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [RD.panelAlt, RD.panel],
        ),
      ),
      child: Center(
        child: loading
            ? const CircularProgressIndicator(color: RD.green)
            : const Icon(Icons.auto_stories_rounded, size: 40, color: RD.textSecondary),
      ),
    );
  }
}
