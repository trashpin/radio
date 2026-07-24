import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/features/destinations/providers/favorites_provider.dart';

/// A reusable heart toggle bound to the favorites state.
///
/// Given a [destinationId] it reflects whether that destination is favorited
/// and toggles it on tap. Being self-contained (it reads/writes the favorites
/// provider itself) means it can be dropped into any card, list tile, or the
/// details screen — and later the Profile screen — without extra wiring.
///
/// [outlineColor] lets callers make the unselected heart legible over imagery
/// (e.g. white on the featured card); the selected heart always uses the brand
/// accent for a consistent "saved" cue.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({
    super.key,
    required this.destinationId,
    this.outlineColor,
  });

  final String destinationId;
  final Color? outlineColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite = ref.watch(
      favoritesProvider.select((ids) => ids.contains(destinationId)),
    );
    final theme = Theme.of(context);

    return IconButton(
      tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
      onPressed: () =>
          ref.read(favoritesProvider.notifier).toggle(destinationId),
      icon: Icon(
        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: isFavorite
            ? AppColors.secondary
            : (outlineColor ?? theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
