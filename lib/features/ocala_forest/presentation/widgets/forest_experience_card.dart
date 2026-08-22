import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/features/around_me/models/experience.dart';
import 'package:explorer_os_mobile/features/ocala_forest/models/forest_location.dart';
import 'package:explorer_os_mobile/features/ocala_forest/services/forest_playback.dart';
import 'package:explorer_os_mobile/features/radio/design/radio_design.dart';

/// A "What's Around Me" card for one forest [Experience] — visually modeled
/// on the existing `ExperienceCard` (`lib/features/around_me/presentation/widgets/experience_card.dart`)
/// for consistency, but wired to `requestInterruption`/Navigate/Tell Me
/// More via [ForestLocation] (`forest_playback.dart`) instead of the
/// Marion-specific `playbackManagerProvider` `ExperienceCard` uses — this
/// app's existing narration mechanism, not a second audio system.
class ForestExperienceCard extends ConsumerWidget {
  const ForestExperienceCard({
    super.key,
    required this.experience,
    required this.location,
    required this.onTellMeMore,
  });

  final Experience experience;
  final ForestLocation location;
  final VoidCallback onTellMeMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: RD.md),
      decoration: BoxDecoration(
        color: RD.panel,
        borderRadius: BorderRadius.circular(RD.rLg),
        border: Border.all(color: RD.stroke),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((experience.imageUrl ?? '').trim().isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(experience.imageUrl!, fit: BoxFit.cover),
            ),
          Padding(
            padding: const EdgeInsets.all(RD.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(experience.name,
                          style: RD.cardTitle.copyWith(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    _distanceDirection(),
                  ],
                ),
                const SizedBox(height: 2),
                Text(experience.category,
                    style: RD.caption.copyWith(color: RD.textSecondary)),
                if ((experience.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: RD.sm),
                  Text(experience.description!,
                      style: RD.body.copyWith(color: RD.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: RD.md),
                Wrap(
                  spacing: RD.sm,
                  runSpacing: RD.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => playForestLocation(ref, location),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Listen'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onTellMeMore,
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      label: const Text('Tell Me More'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => navigateToForestLocation(location),
                      icon: const Icon(Icons.directions_rounded, size: 18),
                      label: const Text('Navigate'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _distanceDirection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(experience.distanceMeters < 1609.344
            ? '${(experience.distanceMeters * 3.28084).round()} ft'
            : '${(experience.distanceMeters / 1609.344).toStringAsFixed(1)} mi',
            style: RD.badge.copyWith(color: RD.textPrimary)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Transform.rotate(
            angle: experience.bearingDegrees * math.pi / 180,
            child: const Icon(Icons.navigation_rounded,
                size: 14, color: RD.greenBright),
          ),
          const SizedBox(width: 2),
          Text(cardinalShort(experience.direction),
              style: RD.caption.copyWith(color: RD.textSecondary)),
        ]),
      ],
    );
  }
}
