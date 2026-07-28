import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:explorer_os_mobile/core/navigation/app_routes.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/destinations/content_engine/content_engine_providers.dart';
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
                  const Gap.v(AppSpacing.xl),
                  _ExperienceSection(destinationCode: destination.id),
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

/// "Explore this destination" — powered by the Content Relationship Engine.
///
/// Loads everything linked to the destination's code in one call
/// ([loadDestinationExperience]) and renders whatever exists: a media gallery,
/// wildlife/plants, nearby attractions, and a content summary.
class _ExperienceSection extends ConsumerWidget {
  const _ExperienceSection({required this.destinationCode});

  final String destinationCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(destinationExperienceProvider(destinationCode));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (exp) {
        if (!exp.isFound) return const SizedBox.shrink();
        final counts = exp.counts;
        final chips = <Widget>[
          if (counts['wildlife']! > 0) _chip(theme, '${counts['wildlife']} wildlife'),
          if (counts['plants']! > 0) _chip(theme, '${counts['plants']} plants'),
          if (counts['narration']! > 0) _chip(theme, '${counts['narration']} narrations'),
          if (counts['stories']! > 0) _chip(theme, '${counts['stories']} stories'),
          if (counts['music']! > 0) _chip(theme, '${counts['music']} tracks'),
          if (counts['nearby']! > 0) _chip(theme, '${counts['nearby']} nearby'),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Explore this destination',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const Gap.v(AppSpacing.md),
            if (chips.isEmpty)
              Text('Content is being produced for this destination.',
                  style: theme.textTheme.bodySmall)
            else
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: chips),
            if (exp.media.gallery.isNotEmpty) ...[
              const Gap.v(AppSpacing.lg),
              _subhead(theme, 'Gallery'),
              const Gap.v(AppSpacing.sm),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: exp.media.gallery.length,
                  separatorBuilder: (_, _) => const Gap.h(AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final url = exp.media.gallery[i].publicUrl;
                    return ClipRRect(
                      borderRadius: AppRadius.mdAll,
                      child: (url ?? '').isEmpty
                          ? const SizedBox(width: 128)
                          : Image.network(url!,
                              width: 128, height: 96, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox(width: 128)),
                    );
                  },
                ),
              ),
            ],
            if (exp.wildlife.isNotEmpty) ...[
              const Gap.v(AppSpacing.lg),
              _subhead(theme, 'Wildlife'),
              const Gap.v(AppSpacing.xs),
              _nameWrap(theme, exp.wildlife.map((s) => s.commonName)),
            ],
            if (exp.plants.isNotEmpty) ...[
              const Gap.v(AppSpacing.lg),
              _subhead(theme, 'Plants & trees'),
              const Gap.v(AppSpacing.xs),
              _nameWrap(theme, exp.plants.map((s) => s.commonName)),
            ],
            if (exp.nearby.isNotEmpty) ...[
              const Gap.v(AppSpacing.lg),
              _subhead(theme, 'Nearby'),
              const Gap.v(AppSpacing.xs),
              for (final n in exp.nearby.take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(Icons.place_outlined,
                        size: 16, color: theme.colorScheme.primary),
                    const Gap.h(AppSpacing.sm),
                    Expanded(
                        child: Text(n.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _subhead(ThemeData theme, String s) => Text(s,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700));

  Widget _chip(ThemeData theme, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: AppRadius.pillAll,
        ),
        child: Text(label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700)),
      );

  Widget _nameWrap(ThemeData theme, Iterable<String> names) => Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          for (final n in names.take(12))
            Chip(
              label: Text(n),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
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
