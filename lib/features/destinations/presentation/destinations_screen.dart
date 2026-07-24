import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/core/error/error_handler.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/widgets/destination_filter_chips.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/widgets/destination_list_tile.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/widgets/destination_search_bar.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/widgets/featured_destination_card.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destination_filters.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/shared/components/section_header.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';
import 'package:explorer_os_mobile/shared/widgets/error_view.dart';
import 'package:explorer_os_mobile/shared/widgets/loading_widget.dart';

/// The Explore screen — search, filter, and browse ExplorerOS destinations
/// (all read from the backend).
///
/// Pure presentation: a persistent search bar + category chips header, then an
/// async body that maps [destinationsProvider] to loading / error / empty /
/// data. All filtering/search logic lives in `destination_filters.dart`
/// providers, so this widget only renders state — the core "separate UI from
/// business logic" goal.
class DestinationsScreen extends ConsumerWidget {
  const DestinationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = ref.watch(destinationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            child: Column(
              children: [
                DestinationSearchBar(
                  onChanged: (value) =>
                      ref.read(destinationQueryProvider.notifier).state = value,
                ),
                const Gap.v(AppSpacing.md),
                DestinationFilterChips(
                  selected: ref.watch(destinationCategoryProvider),
                  onSelected: (category) => ref
                      .read(destinationCategoryProvider.notifier)
                      .state = category,
                ),
              ],
            ),
          ),
          Expanded(
            child: destinations.when(
              loading: () =>
                  const LoadingWidget(message: 'Loading destinations…'),
              error: (error, stackTrace) => ErrorView(
                exception: error is AppException
                    ? error
                    : ErrorHandler.from(error, stackTrace),
                onRetry: () => ref.invalidate(destinationsProvider),
              ),
              data: (_) => const _ExploreResults(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The scrollable results body shown once destinations have loaded. Reads the
/// derived filter providers to decide between the Featured + Popular layout and
/// a flat search-results list.
class _ExploreResults extends ConsumerWidget {
  const _ExploreResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(filteredDestinationsProvider);
    final hasFilter = ref.watch(destinationHasActiveFilterProvider);
    final featured = ref.watch(featuredDestinationProvider);

    // Nothing loaded at all.
    if (featured == null) {
      return const _EmptyState(message: 'No destinations found.');
    }

    // When browsing (no active filter), the featured item headlines its own
    // section, so drop it from the "Popular" list to avoid duplication.
    final popular = hasFilter
        ? filtered
        : filtered.where((d) => d.id != featured.id).toList(growable: false);

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(destinationsProvider.future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.sm,
          AppSpacing.xl,
          120,
        ),
        children: [
          if (!hasFilter) ...[
            const SectionHeader(title: 'Featured Destinations'),
            FeaturedDestinationCard(destination: featured),
            const Gap.v(AppSpacing.xxl),
            const SectionHeader(title: 'Popular Near You'),
          ] else
            const SectionHeader(title: 'Results'),
          if (popular.isEmpty && hasFilter)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xxl),
              child: _EmptyState(message: 'No destinations match your search.'),
            )
          else
            ..._popularList(popular),
        ],
      ),
    );
  }

  List<Widget> _popularList(List<Destination> items) {
    final widgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) widgets.add(const Gap.v(AppSpacing.md));
      widgets.add(DestinationListTile(destination: items[i]));
    }
    return widgets;
  }
}

/// Centered empty-state message.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.travel_explore_outlined,
              size: 56, color: theme.colorScheme.primary),
          const Gap.v(AppSpacing.lg),
          Text(message, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
