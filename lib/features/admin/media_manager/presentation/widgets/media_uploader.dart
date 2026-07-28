import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/data/media_manager_repository.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/models/media_asset.dart';
import 'package:explorer_os_mobile/features/admin/media_manager/presentation/widgets/media_widgets.dart';
import 'package:explorer_os_mobile/features/admin/image_match/filename_normalizer.dart';

enum _UploadStage { pending, uploading, done, failed }

class _Upload {
  _Upload(this.name, this.bytesLen);
  final String name;
  final int bytesLen;
  _UploadStage stage = _UploadStage.pending;
  String? message;
  String? url;
}

/// A reusable uploader: choose a category (Storage folder) + media type, pick
/// one or many files, and upload them to Supabase Storage + `media_assets`,
/// with per-file progress. (Browser file selection stands in for OS drag-and-
/// drop, which needs a desktop drag plugin.)
class MediaUploader extends ConsumerStatefulWidget {
  const MediaUploader({
    super.key,
    this.recordId,
    this.recordType,
    this.destinationId,
    this.onUploaded,
  });

  /// Optionally attach uploads to a specific record.
  final String? recordId;
  final String? recordType;
  final String? destinationId;
  final VoidCallback? onUploaded;

  @override
  ConsumerState<MediaUploader> createState() => _MediaUploaderState();
}

class _MediaUploaderState extends ConsumerState<MediaUploader> {
  MediaRecordType _folder = MediaRecordType.animals;
  MediaType _mediaType = MediaType.image;
  final List<_Upload> _uploads = [];
  final Set<String> _usedKeys = {};
  bool _busy = false;

  FileType get _pickerType => switch (_mediaType) {
        MediaType.image => FileType.image,
        MediaType.video => FileType.video,
        MediaType.audio ||
        MediaType.ambient ||
        MediaType.narration =>
          FileType.audio,
        MediaType.document => FileType.any,
      };

  String get _contentType => switch (_mediaType) {
        MediaType.image => 'image/*',
        MediaType.video => 'video/*',
        MediaType.audio ||
        MediaType.ambient ||
        MediaType.narration =>
          'audio/*',
        MediaType.document => 'application/pdf',
      };

  Future<void> _pick({required bool multiple}) async {
    final result = await FilePicker.platform.pickFiles(
      type: _pickerType,
      allowMultiple: multiple,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    await _uploadAll(result.files);
  }

  String _uniqueKey(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    var key = normalizeMatchKey(base);
    if (key.isEmpty) key = 'file';
    var candidate = key;
    var n = 1;
    while (_usedKeys.contains(candidate)) {
      candidate = '$key-$n';
      n++;
    }
    _usedKeys.add(candidate);
    return candidate;
  }

  Future<void> _uploadAll(List<PlatformFile> files) async {
    final repo = ref.read(mediaManagerRepositoryProvider);
    setState(() {
      _busy = true;
      for (final f in files) {
        _uploads.insert(0, _Upload(f.name, f.bytes?.length ?? 0));
      }
    });
    for (final f in files) {
      final item = _uploads.firstWhere((u) => u.name == f.name);
      final bytes = f.bytes;
      if (bytes == null) {
        setState(() {
          item.stage = _UploadStage.failed;
          item.message = 'No file data';
        });
        continue;
      }
      setState(() => item.stage = _UploadStage.uploading);
      try {
        final ext =
            f.name.contains('.') ? f.name.split('.').last.toLowerCase() : 'bin';
        final key = _uniqueKey(f.name);
        final asset = await repo.uploadAndRecord(
          folder: _mediaType == MediaType.video
              ? 'videos'
              : (_mediaType == MediaType.document
                  ? 'documents'
                  : (_mediaType != MediaType.image
                      ? 'audio'
                      : _folder.folder)),
          filename: '$key.$ext',
          bytes: bytes,
          contentType: _contentType,
          mediaType: _mediaType,
          recordId: widget.recordId,
          recordType: widget.recordType ?? _folder.name,
          destinationId: widget.destinationId,
          title: f.name,
          isHero: false,
        );
        setState(() {
          item.stage = _UploadStage.done;
          item.url = asset.publicUrl;
        });
      } catch (e) {
        setState(() {
          item.stage = _UploadStage.failed;
          item.message = '$e';
        });
      }
    }
    setState(() => _busy = false);
    widget.onUploaded?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<MediaType>(
                initialValue: _mediaType,
                decoration: const InputDecoration(
                    labelText: 'Media type', isDense: true, border: OutlineInputBorder()),
                items: [
                  for (final t in MediaType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) => setState(() => _mediaType = t ?? _mediaType),
              ),
            ),
            const Gap.h(AppSpacing.md),
            Expanded(
              child: DropdownButtonFormField<MediaRecordType>(
                initialValue: _folder,
                decoration: const InputDecoration(
                    labelText: 'Category folder',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: [
                  for (final t in MediaRecordType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (t) => setState(() => _folder = t ?? _folder),
              ),
            ),
          ],
        ),
        const Gap.v(AppSpacing.md),
        InkWell(
          onTap: _busy ? null : () => _pick(multiple: true),
          borderRadius: AppRadius.lgAll,
          child: DottedZone(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_upload_rounded,
                    size: 40, color: theme.colorScheme.primary),
                const Gap.v(AppSpacing.sm),
                Text('Drag & drop or click to browse',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text('Uploads to media/${_folderFor()}/',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const Gap.v(AppSpacing.md),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _busy ? null : () => _pick(multiple: false),
            icon: const Icon(Icons.insert_drive_file_rounded, size: 18),
            label: const Text('Single upload'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _busy ? null : () => _pick(multiple: true),
            icon: const Icon(Icons.library_add_rounded, size: 18),
            label: const Text('Multiple upload'),
          ),
        ]),
        if (_uploads.isNotEmpty) ...[
          const Gap.v(AppSpacing.lg),
          for (final u in _uploads) _uploadRow(theme, u),
        ],
      ],
    );
  }

  String _folderFor() => _mediaType == MediaType.video
      ? 'videos'
      : (_mediaType == MediaType.document
          ? 'documents'
          : (_mediaType != MediaType.image ? 'audio' : _folder.folder));

  Widget _uploadRow(ThemeData theme, _Upload u) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          _stageIcon(u.stage),
          const Gap.h(AppSpacing.sm),
          Expanded(
            child: u.stage == _UploadStage.uploading
                ? MediaProgress(label: u.name, value: 0.6, trailing: 'Uploading…')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (u.stage == _UploadStage.failed)
                        Text(u.message ?? 'Failed',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: theme.colorScheme.error, fontSize: 11)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _stageIcon(_UploadStage s) => switch (s) {
        _UploadStage.pending =>
          const Icon(Icons.schedule_rounded, color: Colors.grey, size: 20),
        _UploadStage.uploading => const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2)),
        _UploadStage.done =>
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
        _UploadStage.failed =>
          const Icon(Icons.error_rounded, color: Colors.red, size: 20),
      };
}

/// A dashed drop-zone container.
class DottedZone extends StatelessWidget {
  const DottedZone({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.04),
        borderRadius: AppRadius.lgAll,
        border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
            width: 1.5),
      ),
      child: child,
    );
  }
}
