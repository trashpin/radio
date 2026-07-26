import 'dart:typed_data';

import 'package:dart_tags/dart_tags.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/image_match/filename_normalizer.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';

/// Parsed ID3 metadata from an MP3 (any field may be null).
class Mp3Tags {
  const Mp3Tags({this.title, this.artist, this.album, this.artwork});
  final String? title;
  final String? artist;
  final String? album;
  final Uint8List? artwork;
}

/// Read ID3 tags (Title/Artist/Album + embedded cover art) from MP3 bytes.
/// Never throws — returns an empty [Mp3Tags] if parsing fails.
Future<Mp3Tags> extractMp3Tags(Uint8List bytes) async {
  try {
    final tags =
        await TagProcessor().getTagsFromByteArray(Future.value(bytes));
    String? pick(String key) {
      for (final t in tags) {
        final v = t.tags[key];
        if (v is String) {
          // ID3 strings are often NUL-terminated/padded — strip control chars.
          final cleaned = v.replaceAll(RegExp(r'[\x00-\x1f]'), '').trim();
          if (cleaned.isNotEmpty) return cleaned;
        }
      }
      return null;
    }

    Uint8List? art;
    for (final t in tags) {
      final pic = t.tags['picture'];
      if (pic is Map && pic.isNotEmpty) {
        final data = (pic.values.first as dynamic).imageData;
        if (data is List<int> && data.isNotEmpty) {
          art = Uint8List.fromList(data);
          break;
        }
      }
    }
    return Mp3Tags(
        title: pick('title'),
        artist: pick('artist'),
        album: pick('album'),
        artwork: art);
  } catch (_) {
    return const Mp3Tags();
  }
}

/// Loads songs from the `songs` table (public read).
final radioSongsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await SupabaseService.client
      .from('songs')
      .select()
      .order('created_at', ascending: false) as List;
  return rows.cast<Map<String, dynamic>>();
});

/// Admin → Music Library: upload a song (audio → `music` bucket, artwork →
/// `artwork` bucket) and save metadata to `songs` — instantly playable, no code.
class SongUploaderPage extends ConsumerWidget {
  const SongUploaderPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(radioSongsProvider);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'Music Library',
          subtitle: 'Upload songs (audio + artwork) straight to Supabase',
          actions: [
            OutlinedButton.icon(
              onPressed: () async {
                final r = await FilePicker.platform.pickFiles(
                    type: FileType.audio, allowMultiple: true, withData: true);
                if (r == null || r.files.isEmpty) return;
                if (!context.mounted) return;
                final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => _BulkImportDialog(files: r.files));
                if (ok == true) ref.invalidate(radioSongsProvider);
              },
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
              icon: const Icon(Icons.library_add_rounded, size: 18),
              label: const Text('Bulk import'),
            ),
            const Gap.h(AppSpacing.sm),
            FilledButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                    context: context, builder: (_) => const _SongDialog());
                if (ok == true) ref.invalidate(radioSongsProvider);
              },
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: const Text('Upload song'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        async.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => AdminSectionCard(
              child: AdminEmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Could not load songs.\n$e')),
          data: (songs) => songs.isEmpty
              ? const AdminSectionCard(
                  child: AdminEmptyState(
                      message: 'No songs yet. Click "Upload song".',
                      icon: Icons.library_music_rounded))
              : AdminSectionCard(
                  child: Column(children: [
                    for (final s in songs)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: (s['cover_image'] != null)
                              ? Image.network(s['cover_image'] as String,
                                  width: 48, height: 48, fit: BoxFit.cover,
                                  errorBuilder: (c, e, st) =>
                                      const Icon(Icons.music_note_rounded))
                              : Container(
                                  width: 48,
                                  height: 48,
                                  color:
                                      theme.dividerColor.withValues(alpha: 0.3),
                                  child: const Icon(Icons.music_note_rounded)),
                        ),
                        title: Text((s['title'] ?? 'Untitled') as String,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          if (s['artist'] != null) s['artist'],
                          if (s['station'] != null) s['station'],
                          if (s['genre'] != null) s['genre'],
                          if (s['park_code'] != null) s['park_code'],
                        ].whereType<String>().join('  ·  ')),
                        trailing: (s['is_active'] == true)
                            ? const Chip(label: Text('Active'))
                            : null,
                      ),
                  ]),
                ),
        ),
      ],
    );
  }
}

class _SongDialog extends StatefulWidget {
  const _SongDialog();
  @override
  State<_SongDialog> createState() => _SongDialogState();
}

class _SongDialogState extends State<_SongDialog> {
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _park = TextEditingController(text: 'ocala');
  final _station = TextEditingController(text: 'Country Roads Radio');
  final _genre = TextEditingController(text: 'country');
  Uint8List? _audioBytes;
  String? _audioName;
  Uint8List? _coverBytes;
  String? _coverName;
  bool _saving = false;
  String? _error;
  String? _tagInfo;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _park.dispose();
    _station.dispose();
    _genre.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.audio, withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    setState(() {
      _audioBytes = f.bytes;
      _audioName = f.name;
      _tagInfo = null;
    });
    if (f.bytes != null) await _readTags(f.bytes!, f.name);
  }

  /// Read ID3 tags from the picked MP3 and auto-fill Title/Artist/Album +
  /// embedded cover art (fields the admin hasn't already set).
  Future<void> _readTags(Uint8List bytes, String filename) async {
    final tags = await extractMp3Tags(bytes);
    setState(() {
      if (tags.title != null && _title.text.trim().isEmpty) {
        _title.text = tags.title!;
      }
      if (tags.artist != null && _artist.text.trim().isEmpty) {
        _artist.text = tags.artist!;
      }
      if (tags.artwork != null && _coverBytes == null) {
        _coverBytes = tags.artwork;
        _coverName = 'embedded.jpg';
      }
      final found = [
        if (tags.title != null) 'title',
        if (tags.artist != null) 'artist',
        if (tags.album != null) 'album',
        if (tags.artwork != null) 'artwork',
      ];
      _tagInfo = found.isEmpty
          ? 'No ID3 tags found — enter details manually.'
          : 'Auto-filled from MP3 tags: ${found.join(", ")}.';
    });
  }

  Future<void> _pickCover() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (r != null && r.files.isNotEmpty) {
      setState(() {
        _coverBytes = r.files.first.bytes;
        _coverName = r.files.first.name;
      });
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _audioBytes == null) {
      setState(() => _error = 'Title and an audio file are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = SupabaseService.client;
      final park = _park.text.trim().isEmpty ? 'unknown' : _park.text.trim();
      final key = normalizeMatchKey(_title.text);

      // 1. Upload audio to the music bucket.
      final aext = (_audioName ?? 'mp3').split('.').last.toLowerCase();
      final apath = '$park/$key.$aext';
      await client.storage.from('music').uploadBinary(apath, _audioBytes!,
          fileOptions: FileOptions(upsert: true, contentType: 'audio/$aext'));
      final audioUrl = client.storage.from('music').getPublicUrl(apath);

      // 2. Optional cover art to the artwork bucket.
      String? coverUrl;
      if (_coverBytes != null) {
        final cext = (_coverName ?? 'jpg').split('.').last.toLowerCase();
        final cpath = '$park/$key.$cext';
        await client.storage.from('artwork').uploadBinary(cpath, _coverBytes!,
            fileOptions: FileOptions(upsert: true, contentType: 'image/$cext'));
        coverUrl = client.storage.from('artwork').getPublicUrl(cpath);
      }

      // 3. Save metadata — immediately available for playback.
      await client.from('songs').insert({
        'title': _title.text.trim(),
        'artist': _artist.text.trim().isEmpty ? null : _artist.text.trim(),
        'park_code': park,
        'station': _station.text.trim().isEmpty ? null : _station.text.trim(),
        'genre': _genre.text.trim().isEmpty ? null : _genre.text.trim(),
        'category': 'music',
        'audio_url': audioUrl,
        'cover_image': coverUrl,
        'is_active': true,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Upload failed (signed in + migration 0011 run?): $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload song'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _f(_title, 'Title *'),
            const Gap.v(AppSpacing.sm),
            _f(_artist, 'Artist'),
            const Gap.v(AppSpacing.sm),
            Row(children: [
              Expanded(child: _f(_park, 'Park code')),
              const Gap.h(AppSpacing.sm),
              Expanded(child: _f(_genre, 'Genre')),
            ]),
            const Gap.v(AppSpacing.sm),
            _f(_station, 'Station'),
            const Gap.v(AppSpacing.md),
            Row(children: [
              OutlinedButton.icon(
                onPressed: _pickAudio,
                icon: const Icon(Icons.audiotrack_rounded, size: 18),
                label: Text(_audioName ?? 'Choose audio *'),
              ),
              const Gap.h(AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _pickCover,
                icon: const Icon(Icons.image_rounded, size: 18),
                label: Text(_coverName ?? 'Cover art'),
              ),
            ]),
            if (_coverBytes != null) ...[
              const Gap.v(AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_coverBytes!, height: 64, width: 64,
                      fit: BoxFit.cover),
                ),
              ),
            ],
            if (_tagInfo != null) ...[
              const Gap.v(AppSpacing.sm),
              Row(children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 14, color: Colors.teal),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(_tagInfo!,
                        style: Theme.of(context).textTheme.bodySmall)),
              ]),
            ],
            if (_error != null) ...[
              const Gap.v(AppSpacing.md),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Upload'),
        ),
      ],
    );
  }

  Widget _f(TextEditingController c, String label) => TextField(
      controller: c,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()));
}

enum _Stage { pending, working, done, failed }

class _FileState {
  _FileState(this.name);
  final String name;
  _Stage stage = _Stage.pending;
  String? title;
  String? artist;
  bool hasArt = false;
  String? message;
}

/// Bulk MP3 importer — reads ID3 tags from each picked file (title/artist +
/// embedded cover art), uploads audio + artwork, and inserts a `songs` row.
/// Shared Park/Station/Genre apply to every file; per-file title/artist come
/// from the MP3 tags (falling back to the filename). Shows live per-file
/// progress and works for hundreds of files.
class _BulkImportDialog extends StatefulWidget {
  const _BulkImportDialog({required this.files});
  final List<PlatformFile> files;

  @override
  State<_BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends State<_BulkImportDialog> {
  final _park = TextEditingController(text: 'ocala');
  final _station = TextEditingController(text: 'Country Roads Radio');
  final _genre = TextEditingController(text: 'country');
  late final List<_FileState> _items =
      widget.files.map((f) => _FileState(f.name)).toList();
  final Set<String> _usedKeys = {};
  bool _running = false;
  bool _finished = false;
  int _ok = 0;
  int _fail = 0;

  @override
  void dispose() {
    _park.dispose();
    _station.dispose();
    _genre.dispose();
    super.dispose();
  }

  String _stripExt(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// Ensure a storage-safe key that is unique within this batch (so two songs
  /// with the same title don't overwrite each other's files).
  String _uniqueKey(String base) {
    var key = normalizeMatchKey(base);
    if (key.isEmpty) key = 'track';
    var candidate = key;
    var n = 1;
    while (_usedKeys.contains(candidate)) {
      candidate = '$key-$n';
      n++;
    }
    _usedKeys.add(candidate);
    return candidate;
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _ok = 0;
      _fail = 0;
    });
    final client = SupabaseService.client;
    final park = _park.text.trim().isEmpty ? 'unknown' : _park.text.trim();
    final station = _station.text.trim();
    final genre = _genre.text.trim();

    for (var i = 0; i < widget.files.length; i++) {
      final file = widget.files[i];
      final item = _items[i];
      final bytes = file.bytes;
      setState(() => item.stage = _Stage.working);
      if (bytes == null) {
        setState(() {
          item.stage = _Stage.failed;
          item.message = 'No file data.';
          _fail++;
        });
        continue;
      }
      try {
        final tags = await extractMp3Tags(bytes);
        final title = (tags.title != null && tags.title!.trim().isNotEmpty)
            ? tags.title!.trim()
            : _stripExt(file.name);
        item
          ..title = title
          ..artist = tags.artist
          ..hasArt = tags.artwork != null;

        final key = _uniqueKey(title);
        final aext = file.name.contains('.')
            ? file.name.split('.').last.toLowerCase()
            : 'mp3';
        final apath = '$park/$key.$aext';
        await client.storage.from('music').uploadBinary(apath, bytes,
            fileOptions:
                FileOptions(upsert: true, contentType: 'audio/$aext'));
        final audioUrl = client.storage.from('music').getPublicUrl(apath);

        String? coverUrl;
        if (tags.artwork != null) {
          final cpath = '$park/$key.jpg';
          await client.storage.from('artwork').uploadBinary(
              cpath, tags.artwork!,
              fileOptions:
                  FileOptions(upsert: true, contentType: 'image/jpeg'));
          coverUrl = client.storage.from('artwork').getPublicUrl(cpath);
        }

        await client.from('songs').insert({
          'title': title,
          'artist': tags.artist,
          'park_code': park,
          'station': station.isEmpty ? null : station,
          'genre': genre.isEmpty ? null : genre,
          'category': 'music',
          'audio_url': audioUrl,
          'cover_image': coverUrl,
          'is_active': true,
        });
        setState(() {
          item.stage = _Stage.done;
          _ok++;
        });
      } catch (e) {
        setState(() {
          item.stage = _Stage.failed;
          item.message = '$e';
          _fail++;
        });
      }
    }
    setState(() {
      _running = false;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Bulk import — ${widget.files.length} files'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: _f(_park, 'Park code')),
            const Gap.h(AppSpacing.sm),
            Expanded(child: _f(_genre, 'Genre')),
          ]),
          const Gap.v(AppSpacing.sm),
          _f(_station, 'Station'),
          const Gap.v(AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _finished
                  ? 'Done — $_ok imported${_fail > 0 ? ', $_fail failed' : ''}.'
                  : _running
                      ? 'Importing… ${_ok + _fail} of ${widget.files.length}'
                      : 'Title & artist auto-fill from each MP3\'s ID3 tags. '
                          'Shared fields above apply to all.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const Gap.v(AppSpacing.sm),
          SizedBox(
            height: 320,
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (c, i) {
                final it = _items[i];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: _stageIcon(it.stage),
                  title: Text(it.title ?? _stripExt(it.name),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    it.stage == _Stage.failed
                        ? (it.message ?? 'Failed')
                        : [
                            if (it.artist != null) it.artist,
                            if (it.hasArt) 'artwork',
                            it.name,
                          ].whereType<String>().join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: it.stage == _Stage.failed
                        ? TextStyle(color: theme.colorScheme.error)
                        : null,
                  ),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context, _ok > 0),
          child: Text(_finished ? 'Close' : 'Cancel'),
        ),
        if (!_finished)
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_upload_rounded, size: 18),
            label: Text(_running
                ? 'Importing…'
                : 'Import ${widget.files.length} songs'),
          ),
      ],
    );
  }

  Widget _stageIcon(_Stage s) {
    switch (s) {
      case _Stage.pending:
        return const Icon(Icons.schedule_rounded, color: Colors.grey);
      case _Stage.working:
        return const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2));
      case _Stage.done:
        return const Icon(Icons.check_circle_rounded, color: Colors.green);
      case _Stage.failed:
        return const Icon(Icons.error_rounded, color: Colors.red);
    }
  }

  Widget _f(TextEditingController c, String label) => TextField(
      controller: c,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()));
}
