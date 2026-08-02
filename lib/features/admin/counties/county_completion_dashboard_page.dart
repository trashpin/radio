import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/location_health.dart';

/// Admin → County Completion Dashboard. Shows content readiness per county —
/// how many cities/communities/attractions exist, how many museums/parks/
/// trails/hidden gems are fully complete, and narration/image/GPS coverage —
/// filterable to one county or all of them at once.
class CountyCompletionDashboardPage extends ConsumerStatefulWidget {
  const CountyCompletionDashboardPage({super.key});

  @override
  ConsumerState<CountyCompletionDashboardPage> createState() =>
      _CountyCompletionDashboardPageState();
}

class _CountyCompletionDashboardPageState
    extends ConsumerState<CountyCompletionDashboardPage> {
  String? _selectedCounty; // null = All Counties

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = ref.watch(masterLocationsProvider).value ?? const [];
    final completions = computeCountyCompletions(all);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('County Completion Dashboard',
              style: theme.textTheme.headlineSmall),
          const Gap.v(AppSpacing.xs),
          Text(
            'Content readiness by county — cities, communities, attractions, '
            'and what still needs images, narration, or GPS verification.',
            style: theme.textTheme.bodySmall,
          ),
          const Gap.v(AppSpacing.md),
          DropdownButtonFormField<String?>(
            initialValue: _selectedCounty,
            decoration: const InputDecoration(
              labelText: 'County',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All Counties')),
              for (final c in completions)
                DropdownMenuItem(value: c.county, child: Text(c.county)),
            ],
            onChanged: (v) => setState(() => _selectedCounty = v),
          ),
          const Gap.v(AppSpacing.lg),
          if (completions.isEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                borderRadius: AppRadius.lgAll,
                border: Border.all(color: theme.dividerColor),
              ),
              child: Column(
                children: [
                  const Icon(Icons.map_outlined, size: 44),
                  const Gap.v(AppSpacing.sm),
                  const Text('No locations have a county set yet.'),
                ],
              ),
            )
          else if (_selectedCounty == null)
            for (final c in completions) _summaryRow(theme, c)
          else
            _detail(
              theme,
              completions.firstWhere((c) => c.county == _selectedCounty),
            ),
        ],
      ),
    );
  }

  /// Compact per-county row shown in the "All Counties" view.
  Widget _summaryRow(ThemeData theme, CountyCompletion c) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        title: Text(c.county),
        subtitle: Text(
          '${c.totalLocations} locations · ${c.totalCities} cities · '
          '${c.totalCommunities} communities',
        ),
        trailing: _percentBadge(theme, c.overallCompletionPercent),
        onTap: () => setState(() => _selectedCounty = c.county),
      ),
    );
  }

  Widget _percentBadge(ThemeData theme, int percent) {
    final color = percent >= 80
        ? Colors.green
        : (percent >= 40 ? Colors.orange : theme.colorScheme.error);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadius.mdAll,
      ),
      child: Text(
        '$percent%',
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }

  /// Full stat grid for one county.
  Widget _detail(ThemeData theme, CountyCompletion c) {
    Widget stat(String label, String value, IconData icon,
            {Color? tint, String? hint}) =>
        AdminStatCard(
            label: label, value: value, icon: icon, tint: tint, hint: hint);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(c.county, style: theme.textTheme.titleLarge),
            const Gap.h(AppSpacing.sm),
            _percentBadge(theme, c.overallCompletionPercent),
            const Gap.h(AppSpacing.xs),
            Text('overall completion', style: theme.textTheme.bodySmall),
          ],
        ),
        const Gap.v(AppSpacing.md),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.6,
          children: [
            stat('Total Cities', '${c.totalCities}', Icons.location_city_rounded),
            stat('Total Communities', '${c.totalCommunities}',
                Icons.holiday_village_rounded),
            stat('Total Attractions', '${c.totalAttractions}',
                Icons.attractions_rounded),
            stat('Museums Complete', '${c.museumsComplete}/${c.museumsTotal}',
                Icons.museum_rounded),
            stat('Parks Complete', '${c.parksComplete}/${c.parksTotal}',
                Icons.forest_rounded),
            stat('Trails Complete', '${c.trailsComplete}/${c.trailsTotal}',
                Icons.hiking_rounded),
            stat('Hidden Gems Complete',
                '${c.hiddenGemsComplete}/${c.hiddenGemsTotal}',
                Icons.diamond_rounded),
            stat('Narrations Complete', '${c.narrationsComplete}',
                Icons.record_voice_over_rounded,
                hint: 'of ${c.totalLocations}'),
            stat('Images Complete', '${c.imagesComplete}', Icons.image_rounded,
                hint: 'of ${c.totalLocations}'),
            stat('GPS Verified', '${c.gpsVerified}', Icons.gps_fixed_rounded,
                hint: 'of ${c.totalLocations}'),
          ],
        ),
      ],
    );
  }
}
