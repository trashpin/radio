import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/logic/media_audit.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';

/// Tone of a [MediaStatusBadge].
enum MediaBadgeTone { ok, warn, missing, info }

/// A small colored status pill (e.g. "Complete", "Missing hero", "Broken").
class MediaStatusBadge extends StatelessWidget {
  const MediaStatusBadge(this.label, {super.key, this.tone = MediaBadgeTone.info});

  final String label;
  final MediaBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      MediaBadgeTone.ok => (const Color(0xFF2E7D32), Colors.white),
      MediaBadgeTone.warn => (const Color(0xFF8A6D00), Colors.white),
      MediaBadgeTone.missing => (const Color(0xFFB3261E), Colors.white),
      MediaBadgeTone.info => (const Color(0xFF2C6E8F), Colors.white),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pillAll),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

/// A labeled progress bar with a percentage — used on the dashboard and per-file
/// upload progress.
class MediaProgress extends StatelessWidget {
  const MediaProgress({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.color,
  });

  /// 0..1
  final double value;
  final String label;
  final String? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600))),
            Text(trailing ?? '${(v * 100).round()}%',
                style: theme.textTheme.bodySmall),
          ],
        ),
        const Gap.v(AppSpacing.xs),
        ClipRRect(
          borderRadius: AppRadius.pillAll,
          child: LinearProgressIndicator(
            value: v,
            minHeight: 8,
            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            color: color ?? theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

/// Renders a small preview for any media asset (image thumbnail, or a typed
/// icon for audio/video/document).
class MediaPreview extends StatelessWidget {
  const MediaPreview({
    super.key,
    this.url,
    this.mediaType = MediaType.image,
    this.size = 48,
    this.radius = 8,
  });

  final String? url;
  final MediaType mediaType;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: size,
      height: size,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(_iconFor(mediaType),
          size: size * 0.45, color: theme.disabledColor),
    );
    final child = (mediaType == MediaType.image && (url ?? '').isNotEmpty)
        ? Image.network(url!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => placeholder)
        : placeholder;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }

  static IconData _iconFor(MediaType t) => switch (t) {
        MediaType.image => Icons.image_rounded,
        MediaType.video => Icons.videocam_rounded,
        MediaType.audio => Icons.audiotrack_rounded,
        MediaType.ambient => Icons.graphic_eq_rounded,
        MediaType.narration => Icons.record_voice_over_rounded,
        MediaType.document => Icons.picture_as_pdf_rounded,
      };
}

/// A card representing a single media asset (preview + metadata + optional
/// delete).
class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.asset, this.onDelete, this.onTap});

  final MediaAsset asset;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.4,
              child: MediaPreview(
                  url: asset.thumbnail ?? asset.publicUrl,
                  mediaType: asset.mediaType,
                  size: 200,
                  radius: 0),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(asset.title ?? asset.storagePath ?? 'Untitled',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Gap.v(AppSpacing.xs),
                  Row(
                    children: [
                      MediaStatusBadge(asset.mediaType.label,
                          tone: MediaBadgeTone.info),
                      if (asset.isHero) ...[
                        const Gap.h(AppSpacing.xs),
                        const MediaStatusBadge('Hero',
                            tone: MediaBadgeTone.ok),
                      ],
                      const Spacer(),
                      if (onDelete != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A responsive grid of [MediaCard]s.
class MediaGallery extends StatelessWidget {
  const MediaGallery({super.key, required this.assets, this.onDelete});

  final List<MediaAsset> assets;
  final void Function(MediaAsset asset)? onDelete;

  @override
  Widget build(BuildContext context) {
    if (assets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: Text('No media yet.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final columns = (c.maxWidth / 220).floor().clamp(1, 6);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: assets.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: 0.95,
        ),
        itemBuilder: (context, i) => MediaCard(
          asset: assets[i],
          onDelete: onDelete == null ? null : () => onDelete!(assets[i]),
        ),
      );
    });
  }
}

/// One row of the Media Audit table.
class MediaAuditRow extends StatelessWidget {
  const MediaAuditRow({super.key, required this.audit});

  final RecordAudit audit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flags = <Widget>[
      if (audit.missingHero) const MediaStatusBadge('No hero', tone: MediaBadgeTone.missing),
      if (audit.missingGallery) const MediaStatusBadge('No gallery', tone: MediaBadgeTone.warn),
      if (audit.missingAudio) const MediaStatusBadge('No audio', tone: MediaBadgeTone.warn),
      if (audit.missingAltText) const MediaStatusBadge('No alt', tone: MediaBadgeTone.warn),
      if (audit.missingCopyright) const MediaStatusBadge('No ©', tone: MediaBadgeTone.warn),
      if (audit.missingCredits) const MediaStatusBadge('No credits', tone: MediaBadgeTone.warn),
      if (audit.brokenFile) const MediaStatusBadge('Broken', tone: MediaBadgeTone.missing),
      if (audit.duplicateFile) const MediaStatusBadge('Duplicate', tone: MediaBadgeTone.missing),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(audit.record.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(audit.record.type.label, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: flags.isEmpty
                  ? const [MediaStatusBadge('Complete', tone: MediaBadgeTone.ok)]
                  : flags,
            ),
          ),
          const Gap.h(AppSpacing.sm),
          SizedBox(
            width: 90,
            child: MediaProgress(
              label: '',
              value: audit.completion,
              trailing: '${(audit.completion * 100).round()}%',
            ),
          ),
        ],
      ),
    );
  }
}
