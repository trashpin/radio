import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/data/media_manager_repository.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/logic/media_audit.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/presentation/widgets/media_uploader.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/presentation/widgets/media_widgets.dart';
import 'package:explorer_os_mobile/features/admin/media_search/presentation/media_search_center_page.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';

/// The Media Manager admin module: a single, comprehensive place to manage
/// every media asset across all ExplorerOS content — Dashboard, Media Library,
/// Media Audit, Upload Center, and Settings.
class MediaManagerPage extends StatelessWidget {
  const MediaManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Dashboard'),
                Tab(text: 'Media Library'),
                Tab(text: 'Search & Import'),
                Tab(text: 'Media Audit'),
                Tab(text: 'Upload Center'),
                Tab(text: 'Settings'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                _DashboardTab(),
                _LibraryTab(),
                MediaSearchCenterPage(),
                _AuditTab(),
                _UploadTab(),
                _SettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(mediaDashboardProvider);
    final total = stats.totalRecords;
    double pct(int missing) =>
        total == 0 ? 0 : (total - missing) / total;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Media Dashboard',
          subtitle: 'Coverage of hero images, galleries, audio and video '
              'across every record.',
        ),
        const Gap.v(AppSpacing.lg),
        LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 220).floor().clamp(2, 5);
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.5,
            children: [
              AdminStatCard(
                  label: 'Total Records',
                  value: '$total',
                  icon: Icons.dataset_rounded),
              AdminStatCard(
                  label: 'Total Images',
                  value: '${stats.totalImages}',
                  icon: Icons.image_rounded,
                  tint: const Color(0xFF2C6E8F)),
              AdminStatCard(
                  label: 'Total Videos',
                  value: '${stats.totalVideos}',
                  icon: Icons.videocam_rounded,
                  tint: const Color(0xFF6A5ACD)),
              AdminStatCard(
                  label: 'Total Audio',
                  value: '${stats.totalAudio}',
                  icon: Icons.audiotrack_rounded,
                  tint: const Color(0xFF2E7D32)),
              AdminStatCard(
                  label: 'Missing Hero',
                  value: '${stats.recordsMissingHero}',
                  icon: Icons.hide_image_rounded,
                  tint: const Color(0xFFB3261E)),
              AdminStatCard(
                  label: 'Missing Gallery',
                  value: '${stats.recordsMissingGallery}',
                  icon: Icons.collections_rounded,
                  tint: const Color(0xFF8A6D00)),
              AdminStatCard(
                  label: 'Missing Audio',
                  value: '${stats.recordsMissingAudio}',
                  icon: Icons.music_off_rounded,
                  tint: const Color(0xFF8A6D00)),
              AdminStatCard(
                  label: 'Broken Links',
                  value: '${stats.brokenImageLinks}',
                  icon: Icons.link_off_rounded,
                  tint: const Color(0xFFB3261E)),
              AdminStatCard(
                  label: 'Duplicate Images',
                  value: '${stats.duplicateImages}',
                  icon: Icons.file_copy_rounded,
                  tint: const Color(0xFF8A6D00)),
              AdminStatCard(
                  label: 'Completion',
                  value: '${stats.completionPercent.round()}%',
                  icon: Icons.verified_rounded,
                  tint: const Color(0xFF2E7D32)),
            ],
          );
        }),
        const Gap.v(AppSpacing.xl),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Media completion',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Gap.v(AppSpacing.md),
              MediaProgress(
                  label: 'Overall completion',
                  value: stats.completionPercent / 100,
                  color: const Color(0xFF2E7D32)),
              const Gap.v(AppSpacing.md),
              MediaProgress(
                  label: 'Records with a hero image',
                  value: pct(stats.recordsMissingHero)),
              const Gap.v(AppSpacing.md),
              MediaProgress(
                  label: 'Records with a gallery',
                  value: pct(stats.recordsMissingGallery)),
              const Gap.v(AppSpacing.md),
              MediaProgress(
                  label: 'Records with audio',
                  value: pct(stats.recordsMissingAudio)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Media Library
// ---------------------------------------------------------------------------

class _LibraryTab extends ConsumerStatefulWidget {
  const _LibraryTab();
  @override
  ConsumerState<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<_LibraryTab> {
  String _query = '';
  MediaRecordType? _category;
  String _missing = 'any'; // any|hero|gallery|audio|video

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audits = ref.watch(mediaAuditProvider);

    final filtered = audits.where((a) {
      if (_category != null && a.record.type != _category) return false;
      if (_query.isNotEmpty &&
          !a.record.title.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      switch (_missing) {
        case 'hero':
          if (!a.missingHero) return false;
        case 'gallery':
          if (!a.missingGallery) return false;
        case 'audio':
          if (!a.missingAudio) return false;
        case 'video':
          if (!a.missingVideo) return false;
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Media Library',
          subtitle: '${filtered.length} of ${audits.length} records',
        ),
        const Gap.v(AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                  hintText: 'Search title…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            _catDropdown(),
            _missingDropdown(),
          ],
        ),
        const Gap.v(AppSpacing.md),
        AdminSectionCard(
          child: Column(
            children: [
              _header(theme),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: AdminEmptyState(
                      icon: Icons.image_search_rounded,
                      message: 'No records match your filters.'),
                )
              else
                for (final a in filtered.take(200)) _row(context, theme, a),
            ],
          ),
        ),
      ],
    );
  }

  Widget _catDropdown() => SizedBox(
        width: 190,
        child: DropdownButtonFormField<MediaRecordType?>(
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Category', isDense: true, border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: null, child: Text('All categories')),
            for (final t in MediaRecordType.values)
              DropdownMenuItem(value: t, child: Text(t.label)),
          ],
          onChanged: (v) => setState(() => _category = v),
        ),
      );

  Widget _missingDropdown() => SizedBox(
        width: 190,
        child: DropdownButtonFormField<String>(
          initialValue: _missing,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Media filter',
              isDense: true,
              border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'any', child: Text('All records')),
            DropdownMenuItem(value: 'hero', child: Text('Missing hero')),
            DropdownMenuItem(value: 'gallery', child: Text('Missing gallery')),
            DropdownMenuItem(value: 'audio', child: Text('Missing audio')),
            DropdownMenuItem(value: 'video', child: Text('Missing video')),
          ],
          onChanged: (v) => setState(() => _missing = v ?? 'any'),
        ),
      );

  Widget _header(ThemeData theme) {
    TextStyle? s = theme.textTheme.labelSmall
        ?.copyWith(fontWeight: FontWeight.w800, color: theme.disabledColor);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(children: [
        SizedBox(width: 52, child: Text('PREVIEW', style: s)),
        Expanded(flex: 3, child: Text('TITLE', style: s)),
        Expanded(flex: 2, child: Text('CATEGORY', style: s)),
        SizedBox(width: 60, child: Text('HERO', style: s)),
        SizedBox(width: 64, child: Text('GALLERY', style: s)),
        SizedBox(width: 50, child: Text('AUDIO', style: s)),
        SizedBox(width: 50, child: Text('VIDEO', style: s)),
        SizedBox(width: 96, child: Text('STATUS', style: s)),
        SizedBox(width: 40, child: Text('', style: s)),
      ]),
    );
  }

  Widget _row(BuildContext context, ThemeData theme, RecordAudit a) {
    Widget flag(bool ok) => Icon(
        ok ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
        size: 16,
        color: ok ? const Color(0xFF2E7D32) : theme.disabledColor);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.3)))),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: MediaPreview(
                url: a.record.heroImageUrl, size: 40, radius: 6),
          ),
          Expanded(
            flex: 3,
            child: Text(a.record.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(
              flex: 2,
              child: Text(a.record.type.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall)),
          SizedBox(width: 60, child: flag(!a.missingHero)),
          SizedBox(
              width: 64,
              child: Text('${a.galleryCount}',
                  style: theme.textTheme.bodySmall)),
          SizedBox(width: 50, child: flag(!a.missingAudio)),
          SizedBox(width: 50, child: flag(!a.missingVideo)),
          SizedBox(
            width: 96,
            child: a.hasIssue
                ? const MediaStatusBadge('Needs media',
                    tone: MediaBadgeTone.warn)
                : const MediaStatusBadge('Complete', tone: MediaBadgeTone.ok),
          ),
          SizedBox(
            width: 40,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 18),
              onSelected: (v) => _action(context, v, a),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'preview', child: Text('Preview')),
                PopupMenuItem(value: 'manage', child: Text('Manage media')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _action(BuildContext context, String v, RecordAudit a) {
    if (v == 'preview') {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(a.record.title),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MediaPreview(
                    url: a.record.heroImageUrl, size: 320, radius: 12),
                const Gap.v(AppSpacing.sm),
                Text('Category: ${a.record.type.label}'),
                Text('Gallery images: ${a.galleryCount}'),
                Text('Audio clips: ${a.audioCount}'),
                Text('Videos: ${a.videoCount}'),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
          ],
        ),
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add media · ${a.record.title}',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const Gap.v(AppSpacing.md),
                    MediaUploader(
                      recordId: a.record.id,
                      recordType: a.record.type.name,
                      destinationId: a.record.destinationId,
                      onUploaded: () =>
                          ref.invalidate(mediaAssetsProvider),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Media Audit
// ---------------------------------------------------------------------------

class _AuditTab extends ConsumerStatefulWidget {
  const _AuditTab();
  @override
  ConsumerState<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends ConsumerState<_AuditTab> {
  bool _issuesOnly = true;

  @override
  Widget build(BuildContext context) {
    final audits = ref.watch(mediaAuditProvider);
    final rows =
        _issuesOnly ? audits.where((a) => a.hasIssue).toList() : audits;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Media Audit',
          subtitle: '${audits.where((a) => a.hasIssue).length} of '
              '${audits.length} records need attention',
          actions: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: audits.isEmpty
                  ? null
                  : () => _exportCsv(context, auditCsv(audits)),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Export CSV'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.sm),
        Row(
          children: [
            FilterChip(
              label: const Text('Issues only'),
              selected: _issuesOnly,
              onSelected: (v) => setState(() => _issuesOnly = v),
            ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        AdminSectionCard(
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: AdminEmptyState(
                      icon: Icons.verified_rounded,
                      message: 'No media issues found.'),
                )
              : Column(
                  children: [
                    for (final a in rows.take(300)) MediaAuditRow(audit: a),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _exportCsv(BuildContext context, String csv) async {
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Audit CSV'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: SingleChildScrollView(
            child: SelectableText(csv,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV copied to clipboard.')),
    );
  }
}

// ---------------------------------------------------------------------------
// Upload Center
// ---------------------------------------------------------------------------

class _UploadTab extends ConsumerWidget {
  const _UploadTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(mediaAssetsProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Upload Center',
          subtitle: 'Upload images, video, audio, ambient, narration and PDFs '
              'straight to Supabase Storage.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: MediaUploader(
            onUploaded: () => ref.invalidate(mediaAssetsProvider),
          ),
        ),
        const Gap.v(AppSpacing.lg),
        Text('Recently uploaded',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const Gap.v(AppSpacing.sm),
        assets.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Could not load media.\n$e')),
          data: (list) => MediaGallery(
            assets: list.take(24).toList(),
            onDelete: (a) async {
              await ref.read(mediaManagerRepositoryProvider).deleteAsset(a.id);
              ref.invalidate(mediaAssetsProvider);
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  static const _folders = [
    'animals/', 'birds/', 'plants/', 'trees/', 'fish/', 'reptiles/',
    'amphibians/', 'flowers/', 'springs/', 'rivers/', 'trails/',
    'campgrounds/', 'historic_sites/', 'visitor_centers/', 'maps/',
    'videos/', 'audio/', 'documents/',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const AdminPageHeader(
          title: 'Media Settings',
          subtitle: 'Storage bucket and folder organization.',
        ),
        const Gap.v(AppSpacing.lg),
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(theme, 'Storage bucket', 'media (public)'),
              _kv(theme, 'Table', 'media_assets'),
              _kv(theme, 'Thumbnails',
                  'Images use their own URL as the thumbnail'),
              const Gap.v(AppSpacing.md),
              Text('Folders',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Gap.v(AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final f in _folders)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: AppRadius.pillAll,
                      ),
                      child: Text(f,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(ThemeData theme, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(
              width: 140,
              child: Text(k,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.disabledColor))),
          Expanded(
              child: Text(v,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600))),
        ]),
      );
}
