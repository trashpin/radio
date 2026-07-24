import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/error/app_exception.dart';
import 'package:explorer_os_mobile/core/error/error_handler.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/destinations/presentation/widgets/destination_card.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';
import 'package:explorer_os_mobile/shared/models/destination.dart';
import 'package:explorer_os_mobile/shared/widgets/error_view.dart';
import 'package:explorer_os_mobile/shared/widgets/loading_widget.dart';

/// The Explore screen — the read-only list of ExplorerOS destinations loaded
/// from the backend.
///
/// Pure presentation: it watches [destinationsProvider] and maps the async
/// state to UI (loading / error / empty / data). No data-access or business
/// logic lives here — that's in the repository and provider — which is the core
/// "separate UI from logic" goal of the refactor.
class DestinationsScreen extends ConsumerWidget {
  const DestinationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = ref.watch(destinationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: destinations.when(
        loading: () => const LoadingWidget(message: 'Loading destinations…'),
        error: (error, stackTrace) => ErrorView(
          exception: error is AppException
              ? error
              : ErrorHandler.from(error, stackTrace),
          onRetry: () => ref.invalidate(destinationsProvider),
        ),
        data: (items) => items.isEmpty
            ? const _EmptyState()
            : _DestinationList(
                items: items,
                onRefresh: () async =>
                    ref.refresh(destinationsProvider.future),
              ),
      ),
    );
  }
}

/// Shown when the backend returns zero destinations.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
          Text('No destinations found.', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Pull-to-refresh list of destination cards.
class _DestinationList extends StatelessWidget {
  const _DestinationList({required this.items, required this.onRefresh});

  final List<Destination> items;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: AppSpacing.screenPadding,
        itemCount: items.length,
        separatorBuilder: (_, _) => const Gap.v(AppSpacing.lg),
        itemBuilder: (context, index) =>
            DestinationCard(destination: items[index]),
      ),
    );
  }
}
