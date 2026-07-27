import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/features/admin/csv/csv_import_logic.dart';
import 'package:explorer_os_mobile/features/admin/widgets/admin_widgets.dart';

/// CSV Importer tab: choose a target, upload a CSV, map columns, validate,
/// preview, then import into Supabase with a per-row error report. The parse,
/// mapping, validation and record-building logic lives in `csv_import_logic.dart`
/// (pure + unit-tested); this widget is only the UI around it.
class CsvImporterTab extends StatefulWidget {
  const CsvImporterTab({super.key, this.debugHeaders, this.debugRows});

  /// Test-only: pre-load a parsed CSV so the mapping/preview/validate UI renders
  /// without a file picker.
  @visibleForTesting
  final List<String>? debugHeaders;
  @visibleForTesting
  final List<List<String>>? debugRows;

  @override
  State<CsvImporterTab> createState() => _CsvImporterTabState();
}

class _CsvImporterTabState extends State<CsvImporterTab> {
  late final List<CsvTarget> _targets = buildCsvTargets();
  late CsvTarget _target = _targets.first;

  String? _fileName;
  String? _loadNote; // visible feedback about the last file pick/parse
  List<String> _headers = const [];
  List<List<String>> _rows = const []; // data rows (no header)
  Map<String, String?> _mapping = {}; // DB column key -> CSV header (or null)

  @override
  void initState() {
    super.initState();
    if (widget.debugHeaders != null) {
      _fileName = 'debug.csv';
      _headers = widget.debugHeaders!;
      _rows = widget.debugRows ?? const [];
      _mapping = autoMapColumns(_headers, _target);
    }
  }

  bool _importing = false;
  int _inserted = 0;
  int _failed = 0;
  final List<String> _errors = [];
  bool _done = false;

  void _onTargetChanged(CsvTarget? t) {
    if (t == null) return;
    setState(() {
      _target = t;
      _mapping = autoMapColumns(_headers, _target);
      _resetResult();
    });
  }

  void _resetResult() {
    _inserted = 0;
    _failed = 0;
    _errors.clear();
    _done = false;
  }

  Future<void> _pickCsv() async {
    FilePickerResult? res;
    try {
      // FileType.any (no extension filter) is the most robust on web/desktop —
      // an extension filter can hide the file in the OS picker.
      res = await FilePicker.platform.pickFiles(withData: true);
    } catch (e) {
      setState(() => _loadNote = 'Could not open the file picker: $e');
      return;
    }
    if (res == null || res.files.isEmpty) {
      setState(() => _loadNote = 'No file selected.');
      return;
    }
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _loadNote =
          'Could not read "${f.name}" (no data). Try re-selecting the file.');
      return;
    }
    _parse(bytes, f.name);
  }

  void _parse(Uint8List bytes, String name) {
    try {
      final content = utf8.decode(bytes, allowMalformed: true);
      final normalized =
          content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final table = Csv(dynamicTyping: false).decode(normalized);
      if (table.isEmpty) {
        setState(() {
          _fileName = name;
          _headers = const [];
          _rows = const [];
          _loadNote = 'No rows found in "$name". Is it a CSV with a header row?';
        });
        return;
      }
      final headers =
          table.first.map((c) => c.toString().trim()).toList(growable: false);
      final rows = <List<String>>[];
      for (final r in table.skip(1)) {
        if (r.every((c) => c.toString().trim().isEmpty)) continue;
        rows.add(r.map((c) => c.toString()).toList(growable: false));
      }
      setState(() {
        _fileName = name;
        _headers = headers;
        _rows = rows;
        _mapping = autoMapColumns(_headers, _target);
        _resetResult();
        _loadNote = 'Loaded "$name": ${rows.length} rows, ${headers.length} columns.';
      });
    } catch (e) {
      setState(() {
        _fileName = name;
        _loadNote = 'Could not parse "$name" as CSV: $e';
        _headers = const [];
        _rows = const [];
        _errors
          ..clear()
          ..add('Could not parse CSV: $e');
      });
    }
  }

  String? _cell(List<String> row, String? header) =>
      cellFor(_headers, row, header);

  int get _invalidRows {
    var n = 0;
    for (final r in _rows) {
      if (buildRecord(_target, _headers, r, _mapping) == null) n++;
    }
    return n;
  }

  bool get _requiredMapped => requiredMapped(_target, _mapping);

  // Columns dropped mid-import because the table doesn't have them (schema
  // drift, e.g. `match_key` before migration 0006). Tracked so we don't fail
  // the whole import over an optional column.
  final Set<String> _droppedColumns = {};

  static String? _missingColumn(String message) =>
      RegExp(r"Could not find the '([^']+)' column").firstMatch(message)?.group(1);

  Map<String, dynamic> _stripDropped(Map<String, dynamic> rec) {
    if (_droppedColumns.isEmpty) return rec;
    final m = Map<String, dynamic>.from(rec);
    for (final c in _droppedColumns) {
      m.remove(c);
    }
    return m;
  }

  /// Inserts records, and if the table is missing a (non-required) column, drops
  /// that column and retries so the rest of the data still saves.
  Future<void> _insertResilient(List<Map<String, dynamic>> records) async {
    final client = SupabaseService.client;
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        await client
            .from(_target.table)
            .insert(records.map(_stripDropped).toList());
        return;
      } catch (e) {
        final col = _missingColumn('$e');
        if (col != null && !_droppedColumns.contains(col)) {
          _droppedColumns.add(col);
          continue; // retry without that column
        }
        rethrow;
      }
    }
  }

  Future<void> _import() async {
    setState(() {
      _importing = true;
      _resetResult();
      _droppedColumns.clear();
    });
    final valid = <Map<String, dynamic>>[];
    var invalid = 0;
    for (final r in _rows) {
      final rec = buildRecord(_target, _headers, r, _mapping);
      if (rec == null) {
        invalid++;
      } else {
        valid.add(rec);
      }
    }
    const batch = 100;
    for (var i = 0; i < valid.length; i += batch) {
      final chunk = valid.sublist(i, min(i + batch, valid.length));
      try {
        await _insertResilient(chunk);
        _inserted += chunk.length;
      } catch (_) {
        // Retry row-by-row to isolate the failures.
        for (final rec in chunk) {
          try {
            await _insertResilient([rec]);
            _inserted++;
          } catch (e2) {
            _failed++;
            if (_errors.length < 20) {
              _errors.add('Row "${rec.values.first}": ${_friendly('$e2')}');
            }
          }
        }
      }
      if (mounted) setState(() {});
    }
    setState(() {
      _importing = false;
      _failed += invalid;
      if (invalid > 0) {
        _errors.insert(
            0,
            _target.passthrough
                ? '$invalid empty row(s) skipped.'
                : '$invalid row(s) skipped: missing required field(s).');
      }
      if (_droppedColumns.isNotEmpty) {
        _errors.insert(0,
            'Note: your "${_target.table}" table has no ${_droppedColumns.join(", ")} '
            'column, so that value was not saved (the rest imported fine).');
      }
      _done = true;
    });
  }

  /// Turns common Postgres/PostgREST errors into a plain-English hint.
  String _friendly(String raw) {
    if (raw.contains('does not exist') || raw.contains('PGRST205')) {
      return 'the "${_target.table}" table does not exist yet. $raw';
    }
    if (raw.contains('42501') || raw.contains('row-level security')) {
      return 'permission denied — are you signed in to the admin? $raw';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Columns to preview: raw CSV headers for passthrough targets, otherwise the
    // target's declared columns (mapped to a CSV header).
    final previewCols = _target.passthrough
        ? [for (final h in _headers) (label: h, header: h)]
        : [for (final c in _target.columns) (label: c.label, header: _mapping[c.key])];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        AdminPageHeader(
          title: 'CSV Importer',
          subtitle: 'Bulk-import content from a spreadsheet. Map columns, '
              'preview, validate, then import.',
          actions: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<CsvTarget>(
                initialValue: _target,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Import into',
                    isDense: true,
                    border: OutlineInputBorder()),
                items: [
                  for (final t in _targets)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: _onTargetChanged,
              ),
            ),
          ],
        ),
        const Gap.v(AppSpacing.lg),

        // Step 1 — choose file.
        AdminSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. Choose a CSV file',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Gap.v(AppSpacing.sm),
              Text('Target table: ${_target.table}'
                  '${_target.note != null ? '  ·  ${_target.note}' : ''}',
                  style: theme.textTheme.bodySmall),
              const Gap.v(AppSpacing.md),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: _importing ? null : _pickCsv,
                  // Override the theme's full-width button size, otherwise the
                  // button forces infinite width inside this Row.
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg)),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: Text(_fileName ?? 'Choose CSV'),
                ),
                if (_rows.isNotEmpty) ...[
                  const Gap.h(AppSpacing.md),
                  Text('${_rows.length} data rows, ${_headers.length} columns',
                      style: theme.textTheme.bodySmall),
                ],
              ]),
              if (_loadNote != null) ...[
                const Gap.v(AppSpacing.sm),
                Row(children: [
                  Icon(
                      _headers.isEmpty
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_rounded,
                      size: 15,
                      color: _headers.isEmpty
                          ? theme.colorScheme.error
                          : Colors.green),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(_loadNote!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: _headers.isEmpty
                                  ? theme.colorScheme.error
                                  : null))),
                ]),
              ],
            ],
          ),
        ),

        if (_headers.isNotEmpty) ...[
          const Gap.v(AppSpacing.lg),
          // Step 2 — map columns (skipped for direct-mapping targets).
          if (_target.passthrough)
            AdminSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('2. Direct column mapping',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Gap.v(AppSpacing.sm),
                  Text(
                      'Every CSV column is sent straight to the "${_target.table}" '
                      'table by name (header "Destination Type" → column '
                      'destination_type). Values are not validated here — the '
                      'database checks each row and any errors are shown below '
                      'after import. Columns your table does not have are '
                      'ignored automatically.',
                      style: theme.textTheme.bodySmall),
                  const Gap.v(AppSpacing.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final h in _headers)
                        Chip(
                          label: Text('$h → ${passthroughKey(h)}',
                              style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ],
              ),
            )
          else
            AdminSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('2. Map columns',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Gap.v(AppSpacing.sm),
                  Text('Match each field to a column from your file '
                      '(auto-guessed where possible).',
                      style: theme.textTheme.bodySmall),
                  const Gap.v(AppSpacing.md),
                  for (final col in _target.columns)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(children: [
                        SizedBox(
                          width: 200,
                          child: Text(col.label + (col.required ? ' *' : ''),
                              style: TextStyle(
                                  fontWeight: col.required
                                      ? FontWeight.w700
                                      : FontWeight.w500)),
                        ),
                        Expanded(
                          child: DropdownButtonFormField<String?>(
                            initialValue: _mapping[col.key],
                            isExpanded: true,
                            decoration: const InputDecoration(
                                isDense: true, border: OutlineInputBorder()),
                            items: [
                              const DropdownMenuItem<String?>(
                                  value: null, child: Text('(skip)')),
                              for (final h in _headers)
                                DropdownMenuItem(value: h, child: Text(h)),
                            ],
                            onChanged: (v) =>
                                setState(() => _mapping[col.key] = v),
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),

          const Gap.v(AppSpacing.lg),
          // Step 3 — preview + validation.
          AdminSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('3. Preview & validate',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Gap.v(AppSpacing.sm),
                Row(children: [
                  _pill(context, Icons.check_circle_rounded,
                      '${_rows.length - _invalidRows} ready', Colors.green),
                  if (_invalidRows > 0) ...[
                    const Gap.h(AppSpacing.sm),
                    _pill(
                        context,
                        Icons.warning_amber_rounded,
                        _target.passthrough
                            ? '$_invalidRows empty'
                            : '$_invalidRows missing required',
                        Colors.orange),
                  ],
                  if (!_target.passthrough && !_requiredMapped) ...[
                    const Gap.h(AppSpacing.sm),
                    _pill(context, Icons.error_rounded,
                        'Map required fields first', Colors.red),
                  ],
                  if (_target.passthrough) ...[
                    const Gap.h(AppSpacing.sm),
                    _pill(context, Icons.storage_rounded,
                        'Validated by database', Colors.blueGrey),
                  ],
                ]),
                const Gap.v(AppSpacing.md),
                // A horizontally-scrollable, explicitly width-bounded table.
                // (A DataTable inside a horizontal scroll view triggers an
                // "infinite width" layout error on the web renderer.)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: (previewCols.isEmpty ? 1 : previewCols.length) * 160.0,
                    child: Table(
                      border: TableBorder.all(
                          color: theme.dividerColor.withValues(alpha: 0.4)),
                      defaultColumnWidth: const FixedColumnWidth(160),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.04)),
                          children: [
                            for (final col in previewCols)
                              _cellText(col.label, bold: true),
                          ],
                        ),
                        for (final r in _rows.take(8))
                          TableRow(children: [
                            for (final col in previewCols)
                              _cellText(_cell(r, col.header) ?? '—'),
                          ]),
                      ],
                    ),
                  ),
                ),
                if (_rows.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text('…and ${_rows.length - 8} more rows',
                        style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),

          const Gap.v(AppSpacing.lg),
          // Step 4 — import.
          AdminSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('4. Import',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Gap.v(AppSpacing.md),
                FilledButton.icon(
                  onPressed: (_importing || !_requiredMapped || _rows.isEmpty)
                      ? null
                      : _import,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg)),
                  icon: _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text(_importing
                      ? 'Importing… ($_inserted done)'
                      : 'Import ${_rows.length - _invalidRows} rows into ${_target.table}'),
                ),
                if (_done || _errors.isNotEmpty) ...[
                  const Gap.v(AppSpacing.md),
                  if (_done)
                    Text('Imported $_inserted'
                        '${_failed > 0 ? ', $_failed failed/skipped' : ''}.',
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _failed > 0 ? Colors.orange : Colors.green)),
                  for (final e in _errors) ...[
                    const Gap.v(AppSpacing.xs),
                    Text('• $e',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error)),
                  ],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _cellText(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
        ),
      );

  Widget _pill(BuildContext context, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
