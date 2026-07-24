import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/shared/components/app_card.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// The large, image-led "Featured Destination" card at the top of Explore.
///
/// Built on the shared [AppCard]; presents the destination's cover image with a
/// bottom gradient scrim so the overlaid name/location stay legible, plus a
/// chevron affordance. Falls back to a branded placeholder when no image URL is
/// provided by the backend.
class FeaturedDestinationCard extends StatelessWidget {
  const FeaturedDestinationCard({
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
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 190,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _cover(theme),
            // Legibility scrim.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                  stops: [0.45, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.name,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(color: AppColors.textOnPrimary),
                  ),
                  if (destination.location != null) ...[
                    const Gap.v(AppSpacing.xs),
                    Text(
                      destination.location!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textOnPrimary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              right: AppSpacing.md,
              top: AppSpacing.md,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.black.withValues(alpha: 0.35),
                child: const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textOnPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(ThemeData theme) {
    final url = destination.imageUrl;
    if (url == null || url.isEmpty) {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.landscape_rounded,
            size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image_outlined, size: 48),
      ),
    );
  }
}
