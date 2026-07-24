import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destination_filters.dart';

/// The horizontal row of category filter chips (All, Parks, Trails, Scenic
/// Drives).
///
/// Dumb/reusable: it renders the [DestinationCategory] values and reports the
/// [selected] one plus [onSelected]; the screen binds these to the category
/// provider. Styling (selected color, shape) comes from the theme.
class DestinationFilterChips extends StatelessWidget {
  const DestinationFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final DestinationCategory selected;
  final ValueChanged<DestinationCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final category in DestinationCategory.values) ...[
            ChoiceChip(
              label: Text(category.label),
              selected: category == selected,
              onSelected: (_) => onSelected(category),
            ),
            const Gap.h(AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
