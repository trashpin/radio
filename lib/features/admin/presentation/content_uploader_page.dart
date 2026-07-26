import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/image_match/filename_normalizer.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';

/// One editable field in a content form.
class FieldSpec {
  const FieldSpec(this.key, this.label,
      {this.multiline = false,
      this.number = false,
      this.options,
      this.defaultValue,
      this.required = false});
  final String key;
  final String label;
  final bool multiline;
  final bool number;
  final List<String>? options; // dropdown
  final String? defaultValue;
  final bool required;
}

/// Config for a generic content table uploader (stories/wildlife/safety/…).
class ContentConfig {
  const ContentConfig({
    required this.table,
    required this.title,
    required this.subtitle,
    required this.titleColumn,
    required this.subtitleColumns,
    required this.fields,
    this.defaults = const {},
    this.audioBucket,
    this.audioColumn,
    this.orderBy = 'created_at',
    this.generatedIdColumn,
  });
  final String table;
  final String title;
  final String subtitle;
  final String titleColumn;
  final List<String> subtitleColumns;
  final List<FieldSpec> fields;
  final Map<String, dynamic> defaults; // e.g. {active:true, published:true}
  final String? audioBucket; // e.g. 'voiceovers'
  final String? audioColumn; // e.g. 'audio_url'
  final String orderBy;

  /// PK column that has no DB default and must be supplied (e.g. stories.story_id).
  final String? generatedIdColumn;
}

/// Random v4 UUID for tables whose PK lacks a default.
String _uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).toList();
  return '${h.sublist(0, 4).join()}-${h.sublist(4, 6).join()}-'
      '${h.sublist(6, 8).join()}-${h.sublist(8, 10).join()}-'
      '${h.sublist(10, 16).join()}';
}

/// A reusable admin page: list rows of [config.table] + an "Add" dialog that
/// saves a row (and optionally uploads a voiceover to Storage). Powers the
/// Stories, Wildlife Alerts, and Safety Messages uploaders.
class ContentUploaderPage extends ConsumerStatefulWidget {
  const ContentUploaderPage(this.config, {super.key});
  final ContentConfig config;
  @override
  ConsumerState<ContentUploaderPage> createState() =>
      _ContentUploaderPageState();
}

class _ContentUploaderPageState extends ConsumerState<ContentUploaderPage> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await SupabaseService.client
        .from(widget.config.table)
        .select()
        .order(widget.config.orderBy, ascending: false) as List;
    return rows.cast<Map<String, dynamic>>();
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: c.title,
          subtitle: c.subtitle,
          actions: [
            FilledButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                    context: context, builder: (_) => _EditDialog(config: c));
                if (ok == true) _refresh();
              },
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return AdminSectionCard(
                  child: AdminEmptyState(
                      icon: Icons.error_outline_rounded,
                      message: 'Could not load ${c.table}.\n${snap.error}'));
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return AdminSectionCard(
                  child: AdminEmptyState(
                      message: 'Nothing yet. Click "Add" to create one.',
                      icon: Icons.inbox_rounded));
            }
            return AdminSectionCard(
              child: Column(children: [
                for (final r in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: (r['audio_url'] != null)
                        ? const Icon(Icons.graphic_eq_rounded,
                            color: Colors.teal)
                        : const Icon(Icons.article_rounded),
                    title: Text((r[c.titleColumn] ?? 'Untitled').toString(),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(c.subtitleColumns
                        .map((k) => r[k])
                        .where((v) => v != null && '$v'.isNotEmpty)
                        .join('  ·  ')),
                  ),
              ]),
            );
          },
        ),
      ],
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.config});
  final ContentConfig config;
  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final _values = <String, String>{};
  final _controllers = <String, TextEditingController>{};
  Uint8List? _audioBytes;
  String? _audioName;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final f in widget.config.fields) {
      if (f.options != null) {
        _values[f.key] = f.defaultValue ?? f.options!.first;
      } else {
        _controllers[f.key] =
            TextEditingController(text: f.defaultValue ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
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

  Future<void> _save() async {
    final c = widget.config;
    // Validate required.
    for (final f in c.fields) {
      if (f.required) {
        final v = f.options != null ? _values[f.key] : _controllers[f.key]?.text;
        if (v == null || v.trim().isEmpty) {
          setState(() => _error = '${f.label} is required.');
          return;
        }
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final client = SupabaseService.client;
      final row = <String, dynamic>{...c.defaults};
      if (c.generatedIdColumn != null) row[c.generatedIdColumn!] = _uuidV4();
      for (final f in c.fields) {
        final v = f.options != null
            ? _values[f.key]
            : _controllers[f.key]!.text.trim();
        if (v == null || v.isEmpty) continue;
        row[f.key] = f.number ? int.tryParse(v) : v;
      }
      // Optional voiceover upload.
      if (_audioBytes != null &&
          c.audioBucket != null &&
          c.audioColumn != null) {
        final ext = (_audioName ?? 'mp3').split('.').last.toLowerCase();
        final titleVal = (row[c.titleColumn] ?? 'clip').toString();
        final path = '${normalizeMatchKey(titleVal)}.$ext';
        await client.storage.from(c.audioBucket!).uploadBinary(path, _audioBytes!,
            fileOptions: FileOptions(upsert: true, contentType: 'audio/$ext'));
        row[c.audioColumn!] =
            client.storage.from(c.audioBucket!).getPublicUrl(path);
      }
      await client.from(c.table).insert(row);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Save failed (signed in? storage policy for '
            '${widget.config.audioBucket}?): $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    return AlertDialog(
      title: Text('Add — ${c.title}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in c.fields) ...[
              if (f.options != null)
                DropdownButtonFormField<String>(
                  initialValue: _values[f.key],
                  decoration: InputDecoration(
                      labelText: f.label, border: const OutlineInputBorder()),
                  items: [
                    for (final o in f.options!)
                      DropdownMenuItem(value: o, child: Text(o)),
                  ],
                  onChanged: (v) => setState(() => _values[f.key] = v ?? ''),
                )
              else
                TextField(
                  controller: _controllers[f.key],
                  maxLines: f.multiline ? 3 : 1,
                  keyboardType: f.number ? TextInputType.number : null,
                  decoration: InputDecoration(
                      labelText: f.label + (f.required ? ' *' : ''),
                      border: const OutlineInputBorder()),
                ),
              const Gap.v(AppSpacing.sm),
            ],
            if (c.audioBucket != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _pickAudio,
                  icon: const Icon(Icons.audiotrack_rounded, size: 18),
                  label: Text(_audioName ?? 'Voiceover audio (optional)'),
                ),
              ),
            if (_error != null) ...[
              const Gap.v(AppSpacing.sm),
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
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ── Configs for the three content types ──────────────────────────────────────

const _ocalaDest = '8338b34e-4d8f-4ff8-a8a3-13b7d82feba2';

const wildlifeConfig = ContentConfig(
  table: 'wildlife_alerts',
  title: 'Wildlife Alerts',
  subtitle: 'Wildlife sightings/updates announced on the radio',
  titleColumn: 'title',
  subtitleColumns: ['species', 'severity', 'park_code'],
  defaults: {'active': true},
  audioBucket: 'voiceovers',
  audioColumn: 'audio_url',
  fields: [
    FieldSpec('title', 'Title', required: true),
    FieldSpec('species', 'Species'),
    FieldSpec('message', 'Message', multiline: true),
    FieldSpec('severity', 'Severity',
        options: ['info', 'notice', 'warning'], defaultValue: 'info'),
    FieldSpec('park_code', 'Park code', defaultValue: 'ocala'),
  ],
);

const safetyConfig = ContentConfig(
  table: 'safety_messages',
  title: 'Safety Messages',
  subtitle: 'Safety announcements the radio can interrupt with',
  titleColumn: 'title',
  subtitleColumns: ['type', 'severity', 'park_code'],
  defaults: {'active': true},
  audioBucket: 'voiceovers',
  audioColumn: 'audio_url',
  fields: [
    FieldSpec('title', 'Title', required: true),
    FieldSpec('type', 'Type', options: [
      'bear',
      'heat',
      'flash_flood',
      'lightning',
      'hydration',
      'trail_etiquette',
      'leave_no_trace',
      'other'
    ], defaultValue: 'other'),
    FieldSpec('message', 'Message', multiline: true),
    FieldSpec('severity', 'Severity',
        options: ['info', 'moderate', 'severe', 'extreme'],
        defaultValue: 'info'),
    FieldSpec('priority', 'Priority (0-10)', number: true, defaultValue: '5'),
    FieldSpec('park_code', 'Park code', defaultValue: 'ocala'),
  ],
);

const scheduleConfig = ContentConfig(
  table: 'radio_schedule',
  title: 'Programming Schedule',
  subtitle: 'Rules for what plays when (announcements between songs)',
  titleColumn: 'name',
  subtitleColumns: ['content_type', 'cadence', 'interval_minutes', 'station'],
  defaults: {'active': true},
  fields: [
    FieldSpec('name', 'Rule name', required: true),
    FieldSpec('content_type', 'Content type',
        options: ['safety', 'wildlife', 'story', 'station_id'],
        defaultValue: 'safety'),
    FieldSpec('cadence', 'Cadence',
        options: ['interval', 'hourly', 'time_of_day'],
        defaultValue: 'interval'),
    FieldSpec('interval_minutes', 'Every N minutes',
        number: true, defaultValue: '15'),
    FieldSpec('time_of_day', 'Time of day (HH:MM, if time_of_day)'),
    FieldSpec('station', 'Station (blank = all)'),
    FieldSpec('park_code', 'Park code', defaultValue: 'ocala'),
    FieldSpec('priority', 'Priority (0-10)', number: true, defaultValue: '5'),
  ],
);

const storiesConfig = ContentConfig(
  table: 'stories',
  title: 'Stories',
  subtitle: 'Park stories & narrations (script-based)',
  titleColumn: 'title',
  subtitleColumns: ['story_category'],
  defaults: {'destination_id': _ocalaDest, 'published': true},
  generatedIdColumn: 'story_id',
  audioBucket: 'voiceovers',
  audioColumn: 'audio_url',
  fields: [
    FieldSpec('title', 'Title', required: true),
    FieldSpec('story_category', 'Category', options: [
      'history',
      'native_heritage',
      'wildlife',
      'geology',
      'conservation',
      'fun_facts',
      'legends',
      'safety'
    ], defaultValue: 'history'),
    FieldSpec('short_summary', 'Short summary', multiline: true),
    FieldSpec('full_story', 'Full story', multiline: true),
    FieldSpec('voice_script', 'Voice script (spoken)', multiline: true),
  ],
);
