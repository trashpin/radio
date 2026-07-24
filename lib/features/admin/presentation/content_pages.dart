import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/admin_modules.dart';
import 'package:explorer_os_mobile/features/admin/admin_state.dart';
import 'package:explorer_os_mobile/features/admin/admin_stats.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';
import 'package:explorer_os_mobile/features/destinations/providers/destinations_provider.dart';

/// Parks / Destinations management (reuses `destinationsProvider`).
class ParksPage extends ConsumerWidget {
  const ParksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(destinationsProvider);
    final query = ref.watch(adminSearchProvider).toLowerCase();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Parks',
          subtitle: 'Destinations in the ExplorerOS catalog',
          actions: [
            FilledButton.icon(
              onPressed: () => _comingSoon(context, 'Create park'),
              style: _headerButtonStyle,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New park'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.xl),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => AdminSectionCard(
            child: AdminEmptyState(
                message: 'Could not load parks.\n$e',
                icon: Icons.error_outline_rounded),
          ),
          data: (all) {
            final rows = query.isEmpty
                ? all
                : all
                    .where((d) => d.name.toLowerCase().contains(query))
                    .toList();
            if (rows.isEmpty) {
              return const AdminSectionCard(
                child: AdminEmptyState(message: 'No parks yet.'),
              );
            }
            return AdminSectionCard(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Type')),
                    DataColumn(label: Text('Location')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final d in rows)
                      DataRow(cells: [
                        DataCell(Text(d.name,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600))),
                        DataCell(Text(d.category ?? '—')),
                        DataCell(Text(d.location ?? '—')),
                        DataCell(StatusBadge(d.featured
                            ? BadgeStatus.published
                            : BadgeStatus.draft)),
                        DataCell(IconButton(
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          onPressed: () =>
                              _comingSoon(context, 'Edit ${d.name}'),
                        )),
                      ]),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Media Library — grid of media items (reuses `MediaRepository`).
class MediaLibraryPage extends ConsumerWidget {
  const MediaLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminMediaProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Media Library',
          subtitle: 'Photos, video, and audio in the mp3 bucket',
          actions: [
            FilledButton.icon(
              onPressed: () => _comingSoon(context, 'Upload media'),
              style: _headerButtonStyle,
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: const Text('Upload'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.xl),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => AdminSectionCard(
            child: AdminEmptyState(
                message: 'Could not load media.\n$e',
                icon: Icons.error_outline_rounded),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const AdminSectionCard(
                child: AdminEmptyState(
                    message: 'No media yet — upload to the mp3 bucket.',
                    icon: Icons.perm_media_rounded),
              );
            }
            return LayoutBuilder(builder: (context, c) {
              final cols = (c.maxWidth / 200).floor().clamp(1, 6);
              const gap = AppSpacing.md;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final m in items)
                    SizedBox(
                      width: w,
                      child: _MediaTile(
                        title: m.title ?? 'Untitled',
                        type: m.mediaType,
                        isAudio: m.isAudio,
                        thumb: m.thumbnailUrl,
                      ),
                    ),
                ],
              );
            });
          },
        ),
      ],
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.title,
    required this.type,
    required this.isAudio,
    this.thumb,
  });

  final String title;
  final String type;
  final bool isAudio;
  final String? thumb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.4,
            child: Container(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              child: (thumb != null && thumb!.isNotEmpty)
                  ? Image.network(thumb!, fit: BoxFit.cover)
                  : Icon(
                      isAudio
                          ? Icons.audiotrack_rounded
                          : Icons.image_rounded,
                      color: theme.colorScheme.primary,
                      size: 34,
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(type.isEmpty ? 'media' : type,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stories management (reuses `StoryRepository`).
class StoriesPage extends ConsumerWidget {
  const StoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(adminStoriesProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Stories',
          subtitle: 'Narrations, scripts, and GPS triggers',
          actions: [
            FilledButton.icon(
              onPressed: () => _comingSoon(context, 'Create story'),
              style: _headerButtonStyle,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New story'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.xl),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => AdminSectionCard(
            child: AdminEmptyState(
                message: 'Could not load stories.\n$e',
                icon: Icons.error_outline_rounded),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const AdminSectionCard(
                child: AdminEmptyState(message: 'No stories yet.'),
              );
            }
            return AdminSectionCard(
              child: Column(
                children: [
                  for (final s in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.menu_book_rounded),
                      title: Text(s.title,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        s.body ?? 'No summary',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const StatusBadge(BadgeStatus.published),
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

/// Generic page for modules not yet implemented; keeps the IA navigable and
/// documents scope + the backing Supabase table.
class ModulePlaceholder extends StatelessWidget {
  const ModulePlaceholder({super.key, required this.module});

  final AdminModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: AppRadius.xlAll,
                ),
                child: Icon(module.icon,
                    size: 42, color: theme.colorScheme.primary),
              ),
              const Gap.v(AppSpacing.lg),
              Text(module.title, style: theme.textTheme.headlineLarge),
              const Gap.v(AppSpacing.sm),
              const StatusBadge(BadgeStatus.planned),
              const Gap.v(AppSpacing.md),
              if (module.description.isNotEmpty)
                Text(module.description,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium),
              if (module.table != null) ...[
                const Gap.v(AppSpacing.md),
                Text('Backing table: ${module.table}',
                    style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Header action buttons must not inherit the theme's full-width
/// `minimumSize` (which would collapse the page title beside them).
final ButtonStyle _headerButtonStyle = FilledButton.styleFrom(
  minimumSize: const Size(0, 44),
  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
);

void _comingSoon(BuildContext context, String label) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$label — coming soon')),
  );
}
