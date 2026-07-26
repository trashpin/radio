import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Bucket, FileObject, FileOptions;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/presentation/csv_import_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/narration_studio_page.dart';
import 'package:explorer_os_mobile/features/admin/presentation/song_uploader_page.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';

/// Buckets we consider "media" and expose for uploads in the Media Library tab.
/// Only buckets that actually exist in the project are shown (resolved live).
const List<String> _preferredMediaBuckets = [
  'music',
  'artwork',
  'narration',
  'voiceovers',
  'stories',
  'species_images',
  'videos',
];

/// Live list of storage buckets (id/name/public). Falls back to a known set if
/// the project doesn't allow listing buckets with the current key.
final storageBucketsProvider = FutureProvider<List<String>>((ref) async {
  try {
    final List<Bucket> buckets =
        await SupabaseService.client.storage.listBuckets();
    final names = buckets.map((b) => b.name).toList()..sort();
    if (names.isNotEmpty) return names;
  } catch (_) {}
  return const [
    'music',
    'artwork',
    'narration',
    'voiceovers',
    'stories',
    'species_images',
    'mp3',
    'songs',
  ];
});

/// Media & Imports hub — a single place to upload files to object storage,
/// manage songs, import CSVs, browse all files, and manage narration.
///
/// Architecture (as requested): Vercel runs the app, Supabase Postgres stores
/// records, and Supabase Storage holds the binary files (MP3s, images, video,
/// CSVs). Every uploader here writes the file to Storage and stores only the
/// public URL/path in the database — nothing is written to Vercel's ephemeral
/// filesystem, so uploads persist across deploys and scale as content grows.
class MediaImportsPage extends StatelessWidget {
  const MediaImportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.perm_media_rounded), text: 'Media Library'),
                Tab(icon: Icon(Icons.library_music_rounded), text: 'Music Manager'),
                Tab(icon: Icon(Icons.table_chart_rounded), text: 'CSV Importer'),
                Tab(icon: Icon(Icons.folder_open_rounded), text: 'File Manager'),
                Tab(
                    icon: Icon(Icons.record_voice_over_rounded),
                    text: 'Narration Manager'),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                _MediaLibraryTab(),
                SongUploaderPage(),
                CsvImporterTab(),
                _FileManagerTab(),
                NarrationStudioPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Media Library: upload MP3s / artwork / video to a chosen bucket, then
/// preview, replace (re-upload same name), or delete.
class _MediaLibraryTab extends ConsumerStatefulWidget {
  const _MediaLibraryTab();
  @override
  ConsumerState<_MediaLibraryTab> createState() => _MediaLibraryTabState();
}

class _MediaLibraryTabState extends ConsumerState<_MediaLibraryTab> {
  String? _bucket;

  @override
  Widget build(BuildContext context) {
    final bucketsAsync = ref.watch(storageBucketsProvider);
    return bucketsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load buckets.\n$e')),
      data: (all) {
        // Order preferred media buckets first, then the rest.
        final ordered = <String>[
          ..._preferredMediaBuckets.where(all.contains),
          ...all.where((b) => !_preferredMediaBuckets.contains(b)),
        ];
        _bucket ??= ordered.isNotEmpty ? ordered.first : null;
        if (_bucket == null) {
          return const Center(child: Text('No storage buckets found.'));
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            AdminPageHeader(
              title: 'Media Library',
              subtitle:
                  'Upload MP3s, cover artwork, and video to object storage. '
                  'Files persist across deploys; records store the URL.',
              actions: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _bucket,
                    decoration: const InputDecoration(
                        labelText: 'Bucket',
                        isDense: true,
                        border: OutlineInputBorder()),
                    items: [
                      for (final b in ordered)
                        DropdownMenuItem(value: b, child: Text(b)),
                    ],
                    onChanged: (v) => setState(() => _bucket = v),
                  ),
                ),
              ],
            ),
            const Gap.v(AppSpacing.lg),
            StorageBrowser(
              key: ValueKey(_bucket),
              bucket: _bucket!,
              allowUpload: true,
              allowDelete: true,
            ),
          ],
        );
      },
    );
  }
}

/// File Manager: browse every bucket read-only (name, size, type, date), with
/// delete for cleanup. Reuses the same [StorageBrowser].
class _FileManagerTab extends ConsumerStatefulWidget {
  const _FileManagerTab();
  @override
  ConsumerState<_FileManagerTab> createState() => _FileManagerTabState();
}

class _FileManagerTabState extends ConsumerState<_FileManagerTab> {
  String? _bucket;

  @override
  Widget build(BuildContext context) {
    final bucketsAsync = ref.watch(storageBucketsProvider);
    return bucketsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load buckets.\n$e')),
      data: (all) {
        _bucket ??= all.isNotEmpty ? all.first : null;
        if (_bucket == null) {
          return const Center(child: Text('No storage buckets found.'));
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            AdminPageHeader(
              title: 'File Manager',
              subtitle: 'Browse all stored files: name, size, type, and date.',
              actions: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _bucket,
                    decoration: const InputDecoration(
                        labelText: 'Bucket',
                        isDense: true,
                        border: OutlineInputBorder()),
                    items: [
                      for (final b in all)
                        DropdownMenuItem(value: b, child: Text(b)),
                    ],
                    onChanged: (v) => setState(() => _bucket = v),
                  ),
                ),
              ],
            ),
            const Gap.v(AppSpacing.lg),
            StorageBrowser(
              key: ValueKey('fm-$_bucket'),
              bucket: _bucket!,
              allowUpload: false,
              allowDelete: true,
            ),
          ],
        );
      },
    );
  }
}

/// A path-navigable Supabase Storage browser: lists files/folders in a bucket
/// with size/type/date, previews images and audio, and (optionally) uploads and
/// deletes. Used by both the Media Library and File Manager tabs.
class StorageBrowser extends StatefulWidget {
  const StorageBrowser({
    super.key,
    required this.bucket,
    this.allowUpload = false,
    this.allowDelete = false,
  });

  final String bucket;
  final bool allowUpload;
  final bool allowDelete;

  @override
  State<StorageBrowser> createState() => _StorageBrowserState();
}

class _StorageBrowserState extends State<StorageBrowser> {
  String _path = ''; // current folder within the bucket
  late Future<List<FileObject>> _future = _load();
  bool _busy = false;
  String? _message;

  Future<List<FileObject>> _load() {
    return SupabaseService.client.storage.from(widget.bucket).list(path: _path);
  }

  void _refresh() => setState(() => _future = _load());

  void _enter(String folder) {
    setState(() {
      _path = _path.isEmpty ? folder : '$_path/$folder';
      _future = _load();
    });
  }

  void _goTo(int segmentIndex) {
    final parts = _path.split('/').where((p) => p.isNotEmpty).toList();
    setState(() {
      _path = parts.take(segmentIndex).join('/');
      _future = _load();
    });
  }

  String _full(String name) => _path.isEmpty ? name : '$_path/$name';

  Future<void> _upload() async {
    final res = await FilePicker.platform
        .pickFiles(allowMultiple: true, withData: true);
    if (res == null || res.files.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    var ok = 0;
    var fail = 0;
    for (final f in res.files) {
      final bytes = f.bytes;
      if (bytes == null) {
        fail++;
        continue;
      }
      try {
        await SupabaseService.client.storage.from(widget.bucket).uploadBinary(
              _full(f.name),
              bytes,
              fileOptions: FileOptions(
                  upsert: true, contentType: _contentType(f.name)),
            );
        ok++;
      } catch (_) {
        fail++;
      }
    }
    setState(() {
      _busy = false;
      _message = 'Uploaded $ok file(s)'
          '${fail > 0 ? ', $fail failed (signed in? bucket policy?)' : ''}.';
      _future = _load();
    });
  }

  Future<void> _delete(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text(name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SupabaseService.client.storage
          .from(widget.bucket)
          .remove([_full(name)]);
      setState(() {
        _message = 'Deleted $name';
        _future = _load();
      });
    } catch (e) {
      setState(() => _message = 'Delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = _path.split('/').where((p) => p.isNotEmpty).toList();
    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Breadcrumb.
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    InkWell(
                      onTap: () => _goTo(0),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.folder_rounded,
                            size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(widget.bucket,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    for (var i = 0; i < parts.length; i++) ...[
                      const Text('  /  '),
                      InkWell(
                        onTap: () => _goTo(i + 1),
                        child: Text(parts[i]),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (widget.allowUpload)
                FilledButton.icon(
                  onPressed: _busy ? null : _upload,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg)),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Upload files'),
                ),
            ],
          ),
          if (_message != null) ...[
            const Gap.v(AppSpacing.sm),
            Text(_message!, style: theme.textTheme.bodySmall),
          ],
          const Divider(),
          FutureBuilder<List<FileObject>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return AdminEmptyState(
                    icon: Icons.error_outline_rounded,
                    message: 'Could not list files.\n${snap.error}');
              }
              final items = (snap.data ?? const <FileObject>[])
                  // Supabase returns a placeholder row for empty folders.
                  .where((f) => f.name != '.emptyFolderPlaceholder')
                  .toList();
              // Folders (id == null) first, then files, each alphabetical.
              items.sort((a, b) {
                final af = a.id == null, bf = b.id == null;
                if (af != bf) return af ? -1 : 1;
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });
              if (items.isEmpty) {
                return const AdminEmptyState(
                    icon: Icons.folder_open_rounded,
                    message: 'This folder is empty.');
              }
              return Column(
                children: [
                  for (final f in items)
                    _row(context, f),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, FileObject f) {
    final theme = Theme.of(context);
    final isFolder = f.id == null;
    final size = (f.metadata?['size'] as num?)?.toInt();
    final mime = f.metadata?['mimetype'] as String?;
    final updated = f.updatedAt ?? f.createdAt;
    final subtitle = isFolder
        ? 'Folder'
        : [
            ?mime,
            if (size != null) _fmtSize(size),
            if (updated != null) _fmtDate(updated),
          ].join('  ·  ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isFolder
            ? Icons.folder_rounded
            : _iconFor(mime, f.name),
        color: isFolder ? theme.colorScheme.primary : null,
      ),
      title: Text(f.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: isFolder ? () => _enter(f.name) : () => _preview(context, f),
      trailing: isFolder
          ? const Icon(Icons.chevron_right_rounded)
          : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Preview',
                icon: const Icon(Icons.visibility_rounded, size: 20),
                onPressed: () => _preview(context, f),
              ),
              if (widget.allowDelete)
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: () => _delete(f.name),
                ),
            ]),
    );
  }

  void _preview(BuildContext context, FileObject f) {
    final url = SupabaseService.client.storage
        .from(widget.bucket)
        .getPublicUrl(_full(f.name));
    final mime = f.metadata?['mimetype'] as String?;
    final isImage = (mime?.startsWith('image/') ?? false) ||
        _hasExt(f.name, ['jpg', 'jpeg', 'png', 'webp', 'gif']);
    final isAudio = (mime?.startsWith('audio/') ?? false) ||
        _hasExt(f.name, ['mp3', 'wav', 'm4a', 'aac', 'ogg']);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(f.name),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isImage)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: Image.network(url, fit: BoxFit.contain,
                      errorBuilder: (c, e, s) =>
                          const Text('Could not load image.')),
                )
              else if (isAudio)
                _AudioPreview(url: url)
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Icon(Icons.insert_drive_file_rounded, size: 64),
                ),
              const Gap.v(AppSpacing.md),
              SelectableText(url,
                  style: Theme.of(context).textTheme.bodySmall),
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
  }
}

/// Small inline audio player used in the file preview dialog.
class _AudioPreview extends StatefulWidget {
  const _AudioPreview({required this.url});
  final String url;
  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> {
  final _player = AudioPlayer();
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setUrl(widget.url);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Text('Could not load audio.\n$_error');
    return Row(
      children: [
        StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, snap) {
            final playing = snap.data?.playing ?? false;
            return IconButton.filled(
              iconSize: 28,
              onPressed: !_ready
                  ? null
                  : () => playing ? _player.pause() : _player.play(),
              icon: Icon(playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded),
            );
          },
        ),
        const Gap.h(AppSpacing.sm),
        Expanded(
          child: StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, snap) {
              final pos = snap.data ?? Duration.zero;
              final total = _player.duration ?? Duration.zero;
              final frac = total.inMilliseconds == 0
                  ? 0.0
                  : pos.inMilliseconds / total.inMilliseconds;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: frac.clamp(0.0, 1.0)),
                  const SizedBox(height: 4),
                  Text('${_fmtDur(pos)} / ${_fmtDur(total)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

String _fmtDur(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _fmtDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final l = d.toLocal();
  final mm = l.month.toString().padLeft(2, '0');
  final dd = l.day.toString().padLeft(2, '0');
  return '${l.year}-$mm-$dd';
}

bool _hasExt(String name, List<String> exts) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return exts.contains(name.substring(dot + 1).toLowerCase());
}

IconData _iconFor(String? mime, String name) {
  if ((mime?.startsWith('image/') ?? false) ||
      _hasExt(name, ['jpg', 'jpeg', 'png', 'webp', 'gif'])) {
    return Icons.image_rounded;
  }
  if ((mime?.startsWith('audio/') ?? false) ||
      _hasExt(name, ['mp3', 'wav', 'm4a', 'aac', 'ogg'])) {
    return Icons.audiotrack_rounded;
  }
  if ((mime?.startsWith('video/') ?? false) ||
      _hasExt(name, ['mp4', 'mov', 'webm'])) {
    return Icons.movie_rounded;
  }
  if (_hasExt(name, ['csv'])) return Icons.table_chart_rounded;
  if (_hasExt(name, ['json'])) return Icons.data_object_rounded;
  if (_hasExt(name, ['pdf'])) return Icons.picture_as_pdf_rounded;
  return Icons.insert_drive_file_rounded;
}

String _contentType(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'mp3':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'm4a':
      return 'audio/mp4';
    case 'aac':
      return 'audio/aac';
    case 'ogg':
      return 'audio/ogg';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'mp4':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
    case 'csv':
      return 'text/csv';
    case 'json':
      return 'application/json';
    case 'pdf':
      return 'application/pdf';
    default:
      return 'application/octet-stream';
  }
}
