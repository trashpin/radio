import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/widgets/favorite_button.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/shared/components/primary_button.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';

/// The Destination Details screen.
///
/// Opened by id (a deep-link-friendly route) and resolves the destination via
/// [destinationByIdProvider]. Presents a large hero image with a favorite
/// toggle, then the name, location, category, and description — all read from
/// the backend model. Reuses shared components ([PrimaryButton],
/// [FavoriteButton]) and design-system tokens. Degrades gracefully to a
/// "not found" state if the id isn't in the loaded list.
class DestinationDetailsScreen extends ConsumerWidget {
  const DestinationDetailsScreen({super.key, required this.destinationId});

  final String destinationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = ref.watch(destinationByIdProvider(destinationId));

    if (destination == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Destination not found.')),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _DetailsAppBar(destination: destination),
          SliverToBoxAdapter(
            child: Padding(
              padding: AppSpacing.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(destination.name, style: theme.textTheme.headlineLarge),
                  if (destination.location != null) ...[
                    const Gap.v(AppSpacing.sm),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 18, color: theme.colorScheme.primary),
                        const Gap.h(AppSpacing.xs),
                        Text(destination.location!,
                            style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ],
                  if (destination.category != null) ...[
                    const Gap.v(AppSpacing.md),
                    _CategoryTag(label: destination.category!),
                  ],
                  const Gap.v(AppSpacing.xl),
                  Text(
                    destination.description ??
                        'More information about this destination is coming '
                            'soon.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const Gap.v(AppSpacing.xxl),
                  PrimaryButton(
                    label: 'View on Map',
                    icon: Icons.map_outlined,
                    onPressed: () => context.go(AppRoute.map.path),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsing hero image app bar with a favorite toggle action.
class _DetailsAppBar extends StatelessWidget {
  const _DetailsAppBar({required this.destination});

  final Destination destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage =
        destination.imageUrl != null && destination.imageUrl!.isNotEmpty;

    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      actions: [
        FavoriteButton(
          destinationId: destination.id,
          outlineColor: AppColors.textOnPrimary,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage)
              Image.network(
                destination.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(theme),
              )
            else
              _fallback(theme),
            // Scrim so the back/favorite icons stay visible on bright images.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black45, Colors.transparent, Colors.black26],
                  stops: [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback(ThemeData theme) => ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.landscape_rounded,
            size: 72, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
      );
}

/// Small pill showing the destination category.
class _CategoryTag extends StatelessWidget {
  const _CategoryTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelLarge
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}
