import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/app_exception.dart';
import '../../core/error/error_handler.dart';
import '../../models/destination.dart';
import '../../shared/widgets/error_view.dart';
import '../../shared/widgets/loading_widget.dart';
import 'destinations_provider.dart';

/// The Destinations tab — shows the read-only list of ExplorerOS destinations
/// loaded from the backend.
///
/// It watches [destinationsProvider] and renders one of four states:
///   • loading  → shared `LoadingWidget`
///   • error    → shared `ErrorView` with a friendly message + retry
///   • empty    → "No destinations found."
///   • data     → a scrollable list of destinations
///
/// No destination content is hardcoded; everything comes from Supabase.
class DestinationsScreen extends ConsumerWidget {
  const DestinationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = ref.watch(destinationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Destinations')),
      body: destinations.when(
        loading: () => const LoadingWidget(message: 'Loading destinations…'),
        error: (error, stackTrace) => ErrorView(
          // Normalize anything unexpected into an AppException for a friendly UI.
          exception: error is AppException
              ? error
              : ErrorHandler.from(error, stackTrace),
          onRetry: () => ref.invalidate(destinationsProvider),
        ),
        data: (items) => items.isEmpty
            ? const _EmptyState()
            : _DestinationList(
                items: items,
                onRefresh: () async => ref.refresh(destinationsProvider.future),
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
          const SizedBox(height: AppConstants.spacingMd),
          Text('No destinations found.', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Renders the loaded destinations as pull-to-refresh list of cards.
class _DestinationList extends StatelessWidget {
  const _DestinationList({required this.items, required this.onRefresh});

  final List<Destination> items;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: AppConstants.spacingSm),
        itemBuilder: (context, index) => _DestinationCard(items[index]),
      ),
    );
  }
}

/// A single destination row.
class _DestinationCard extends StatelessWidget {
  const _DestinationCard(this.destination);

  final Destination destination;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
      ),
      child: ListTile(
        leading: destination.imageUrl != null
            ? CircleAvatar(
                backgroundImage: NetworkImage(destination.imageUrl!),
              )
            : const CircleAvatar(child: Icon(Icons.place_outlined)),
        title: Text(destination.name),
        subtitle: destination.description != null
            ? Text(
                destination.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
      ),
    );
  }
}
