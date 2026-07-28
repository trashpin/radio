import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/around_me/models/experience.dart';
import 'package:explorer_os_mobile/features/around_me/providers/around_me_providers.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';
import 'package:explorer_os_mobile/features/maps/providers/nearby_provider.dart';
import 'package:explorer_os_mobile/features/playback/playback_models.dart';
import 'package:explorer_os_mobile/features/playback/playback_providers.dart';

/// A large "experience" card for the Around Me feed: photo, name, distance +
/// direction, category, short description, and Play Narration / Navigate / Save.
class ExperienceCard extends ConsumerWidget {
  const ExperienceCard({super.key, required this.experience});

  final Experience experience;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final style = nearbyStyle(experience.category);
    final saved = ref.watch(savedExperiencesProvider).contains(experience.id);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _photo(context, style),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        experience.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _distanceDirection(theme, style.color),
                  ],
                ),
                const Gap.v(AppSpacing.xs),
                Row(
                  children: [
                    _categoryChip(style),
                    if (experience.featured) ...[
                      const Gap.h(AppSpacing.sm),
                      _pill(theme, 'Featured', const Color(0xFFF2B33D)),
                    ],
                    if (experience.visited) ...[
                      const Gap.h(AppSpacing.sm),
                      _pill(theme, 'Visited', theme.disabledColor),
                    ],
                  ],
                ),
                if ((experience.description ?? '').isNotEmpty) ...[
                  const Gap.v(AppSpacing.sm),
                  Text(
                    experience.description!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const Gap.v(AppSpacing.md),
                _actions(context, ref, saved),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo(BuildContext context, NearbyStyle style) {
    final url = experience.imageUrl;
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _photoFallback(style))
          else
            _photoFallback(style),
          Positioned(
            left: AppSpacing.sm,
            top: AppSpacing.sm,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: AppRadius.pillAll,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 12, color: Color(0xFFF2B33D)),
                const SizedBox(width: 4),
                Text('Score ${experience.score.round()}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoFallback(NearbyStyle style) => Container(
        color: style.color.withValues(alpha: 0.18),
        child: Icon(style.icon, size: 44, color: style.color),
      );

  Widget _distanceDirection(ThemeData theme, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(formatDistance(experience.distanceMeters),
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Transform.rotate(
            angle: experience.bearingDegrees * math.pi / 180,
            child: Icon(Icons.navigation_rounded, size: 14, color: color),
          ),
          const SizedBox(width: 2),
          Text(cardinalShort(experience.direction),
              style: theme.textTheme.bodySmall),
        ]),
      ],
    );
  }

  Widget _categoryChip(NearbyStyle style) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.14),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(style.icon, size: 13, color: style.color),
        const SizedBox(width: 4),
        Text(style.group,
            style: TextStyle(
                color: style.color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _pill(ThemeData theme, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: AppRadius.pillAll,
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _actions(BuildContext context, WidgetRef ref, bool saved) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => _playNarration(context, ref),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Listen'),
          ),
        ),
        const Gap.h(AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => _navigate(context, ref),
            icon: const Icon(Icons.directions_rounded, size: 18),
            label: const Text('Navigate'),
          ),
        ),
        const Gap.h(AppSpacing.sm),
        IconButton.outlined(
          onPressed: () =>
              ref.read(savedExperiencesProvider.notifier).toggle(experience.id),
          icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
          tooltip: saved ? 'Saved' : 'Save',
        ),
      ],
    );
  }

  void _playNarration(BuildContext context, WidgetRef ref) {
    if (!experience.hasNarration) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No narration available for ${experience.name}')),
      );
      return;
    }
    ref.read(playbackManagerProvider).playNarration(
          PlaybackItem(
            type: PlaybackItemType.poi,
            title: experience.name,
            audioUrl: experience.audioUrl!,
            metadata: {'experienceId': experience.id},
          ),
        );
    ref
        .read(aroundMeControllerProvider.notifier)
        .markNarrationPlayed(experience.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playing narration: ${experience.name}')),
    );
  }

  void _navigate(BuildContext context, WidgetRef ref) {
    ref
        .read(mapCenterProvider.notifier)
        .set(LatLng(experience.latitude, experience.longitude));
    context.go(AppRoute.map.path);
  }
}
