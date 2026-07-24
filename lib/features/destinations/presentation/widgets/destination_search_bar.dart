import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';

/// The Explore search field ("Search parks, places, routes…").
///
/// A dumb, reusable input: it owns no state and simply reports text changes via
/// [onChanged], so the screen can wire it to the search provider. Styling comes
/// from the design system (filled, pill-shaped).
class DestinationSearchBar extends StatelessWidget {
  const DestinationSearchBar({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search parks, places, routes…',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: theme.colorScheme.surface,
        contentPadding: EdgeInsets.zero,
        border: const OutlineInputBorder(
          borderRadius: AppRadius.pillAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.pillAll,
          borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.pillAll,
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
