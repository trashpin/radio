import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/widgets/favorite_button.dart';
import 'package:explorer_os_mobile/shared/components/app_card.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// A compact destination row for the "Popular Near You" / results list.
///
/// Built on the shared [AppCard]: a rounded thumbnail, the name and location,
/// and a trailing distance label (when the backend provides one) or a chevron.
/// Distance is shown only if present — never fabricated (live distance arrives
/// with the GPS feature).
class DestinationListTile extends StatelessWidget {
  const DestinationListTile({
    super.key,
    required this.destination,
    this.onTap,
  });

  final Destination destination;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          _Thumbnail(imageUrl: destination.imageUrl),
          const Gap.h(AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(destination.name, style: theme.textTheme.titleMedium),
                if (destination.location != null) ...[
                  const Gap.v(AppSpacing.xs),
                  Text(destination.location!,
                      style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const Gap.h(AppSpacing.sm),
          if (destination.distanceLabel != null)
            Text(
              destination.distanceLabel!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          FavoriteButton(destinationId: destination.id),
        ],
      ),
    );
  }
}

/// Rounded square thumbnail with a graceful fallback.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const size = 60.0;

    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.smAll,
        ),
        child: Icon(Icons.landscape_rounded,
            color: theme.colorScheme.primary.withValues(alpha: 0.5)),
      );
    }

    return ClipRRect(
      borderRadius: AppRadius.smAll,
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}
