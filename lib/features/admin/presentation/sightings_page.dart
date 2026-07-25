import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/admin_state.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/sightings/models/explorer_sighting.dart';
import 'package:explorer_os_mobile/features/sightings/models/sighting_category.dart';
import 'package:explorer_os_mobile/features/sightings/providers/sighting_providers.dart';

/// Admin → Explorer Sightings: view/search/filter/delete/export observations.
class SightingsAdminPage extends ConsumerStatefulWidget {
  const SightingsAdminPage({super.key});

  @override
  ConsumerState<SightingsAdminPage> createState() => _SightingsAdminPageState();
}

class _SightingsAdminPageState extends ConsumerState<SightingsAdminPage> {
  SightingCategory? _categoryFilter;

  List<ExplorerSighting> _filter(List<ExplorerSighting> all, String query) {
    return all.where((s) {
      if (_categoryFilter != null && s.category != _categoryFilter) return false;
      if (query.isEmpty) return true;
      final hay = [
        s.species ?? '',
        s.category.label,
        s.parkName ?? '',
        s.notes ?? '',
      ].join(' ').toLowerCase();
      return hay.contains(query);
    }).toList();
  }

  String _csv(List<ExplorerSighting> rows) {
    final b = StringBuffer(
        'category,species,park,latitude,longitude,notes,created_at\n');
    for (final s in rows) {
      String q(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
      b.writeln([
        q(s.category.label),
        q(s.species),
        q(s.parkName),
        s.latitude ?? '',
        s.longitude ?? '',
        q(s.notes),
        q(s.createdAt?.toIso8601String()),
      ].join(','));
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(recentSightingsProvider);
    final query = ref.watch(adminSearchProvider).toLowerCase();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Explorer Sightings',
          subtitle: 'Citizen-science observations from "I See Something"',
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                final rows = _filter(async.value ?? const [], query);
                final csv = _csv(rows);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      'Exported ${rows.length} sightings (${csv.length} chars CSV)'),
                ));
              },
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Export CSV'),
            ),
            const Gap.h(AppSpacing.sm),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(recentSightingsProvider.notifier).refresh(),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        // Category filter chips
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _categoryFilter == null,
              onSelected: (_) => setState(() => _categoryFilter = null),
            ),
            for (final c in SightingCategory.values)
              ChoiceChip(
                avatar: Icon(c.icon, size: 16),
                label: Text(c.label),
                selected: _categoryFilter == c,
                onSelected: (_) => setState(() => _categoryFilter = c),
              ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => AdminSectionCard(
            child: AdminEmptyState(
              icon: Icons.error_outline_rounded,
              message: 'Could not load sightings.\n'
                  'If the table is missing, run migration 0003_explorer_sightings.sql.\n$e',
            ),
          ),
          data: (all) {
            final rows = _filter(all, query);
            if (rows.isEmpty) {
              return const AdminSectionCard(
                child: AdminEmptyState(
                    message: 'No sightings yet.',
                    icon: Icons.visibility_off_rounded),
              );
            }
            return AdminSectionCard(
              child: Column(
                children: [
                  for (final s in rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        child: Icon(s.category.icon,
                            size: 18, color: theme.colorScheme.primary),
                      ),
                      title: Text(s.species ?? s.category.label,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [
                          s.category.label,
                          if (s.parkName != null) s.parkName,
                          if (s.hasCoordinates)
                            '${s.latitude!.toStringAsFixed(3)}, ${s.longitude!.toStringAsFixed(3)}',
                          if (s.notes != null) s.notes,
                        ].whereType<String>().join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                        onPressed: () => ref
                            .read(recentSightingsProvider.notifier)
                            .remove(s.id),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
