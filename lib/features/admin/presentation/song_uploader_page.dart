import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/image_match/filename_normalizer.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';

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
    if (r != null && r.files.isNotEmpty) {
      setState(() {
        _audioBytes = r.files.first.bytes;
        _audioName = r.files.first.name;
      });
    }
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
