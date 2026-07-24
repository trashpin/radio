import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/shared/components/app_card.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// A single destination presented as a large, image-led card.
///
/// Feature-specific (lives under the destinations feature) but built on the
/// shared [AppCard] so it inherits the app's surface, radius, shadow, and press
/// animation. Extracted from the screen so the list body stays declarative.
class DestinationCard extends StatelessWidget {
  const DestinationCard({super.key, required this.destination, this.onTap});

  final Destination destination;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoverImage(imageUrl: destination.imageUrl),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(destination.name, style: theme.textTheme.titleMedium),
                if (destination.description != null) ...[
                  const Gap.v(AppSpacing.xs),
                  Text(
                    destination.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cover image with a graceful fallback when no image URL is provided.
class _CoverImage extends StatelessWidget {
  const _CoverImage({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const height = 150.0;

    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        height: height,
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.landscape_rounded,
          size: 48,
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      child: Image.network(
        imageUrl!,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          height: height,
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image_outlined, size: 40),
        ),
      ),
    );
  }
}
