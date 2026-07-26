import 'dart:math';

import 'package:explorer_os_mobile/features/admin/image_match/filename_normalizer.dart';

/// One column expected by an import target.
class CsvCol {
  const CsvCol(this.key, this.label,
      {this.required = false, this.number = false});
  final String key; // DB column
  final String label; // human label
  final bool required;
  final bool number;
}

/// A CSV import target: which Supabase table + which columns it accepts.
class CsvTarget {
  const CsvTarget({
    required this.label,
    required this.table,
    required this.columns,
    this.defaults = const {},
    this.generatedIdColumn,
    this.matchKeyFrom,
    this.note,
  });

  final String label;
  final String table;
  final List<CsvCol> columns;
  final Map<String, dynamic> defaults;

  /// PK column with no DB default (a UUID is generated per row).
  final String? generatedIdColumn;

  /// If set, `match_key` is derived from this column (used by species so image
  /// matching works).
  final String? matchKeyFrom;

  /// Optional caveat surfaced in the UI (e.g. table must exist).
  final String? note;

  List<CsvCol> get requiredColumns =>
      columns.where((c) => c.required).toList(growable: false);
}

const _ocalaDest = '8338b34e-4d8f-4ff8-a8a3-13b7d82feba2';

/// Common species columns, reused by the five nature targets (they differ only
/// by the default `category`). Only columns that exist on the `species` table.
const _speciesCols = <CsvCol>[
  CsvCol('common_name', 'Common name', required: true),
  CsvCol('scientific_name', 'Scientific name'),
  CsvCol('description', 'Description'),
  CsvCol('diet', 'Diet'),
  CsvCol('behavior', 'Behavior'),
  CsvCol('conservation_status', 'Conservation status'),
  CsvCol('fun_facts', 'Fun facts'),
  CsvCol('safety_info', 'Safety info'),
  CsvCol('hero_image', 'Hero image URL'),
];

CsvTarget _species(String label, String category) => CsvTarget(
      label: label,
      table: 'species',
      columns: _speciesCols,
      defaults: {
        'category': category,
        'destination_id': _ocalaDest,
        'published': true,
      },
      matchKeyFrom: 'common_name',
    );

/// The supported import targets (one per content type in the brief).
List<CsvTarget> buildCsvTargets() => [
      _species('Wildlife', 'animals'),
      _species('Birds', 'birds'),
      _species('Plants', 'plants'),
      _species('Trees', 'trees'),
      _species('Wildflowers', 'wildflowers'),
      const CsvTarget(
        label: 'Trails',
        table: 'trails',
        note: 'Requires a `trails` table.',
        columns: [
          CsvCol('name', 'Name', required: true),
          CsvCol('difficulty', 'Difficulty'),
          CsvCol('distance_miles', 'Distance (miles)', number: true),
          CsvCol('description', 'Description'),
        ],
        defaults: {'destination_id': _ocalaDest},
      ),
      const CsvTarget(
        label: 'Points of Interest',
        table: 'map_locations',
        note: 'Requires a `map_locations` table (run migration 0009).',
        columns: [
          CsvCol('name', 'Name', required: true),
          CsvCol('category', 'Category'),
          CsvCol('latitude', 'Latitude', number: true),
          CsvCol('longitude', 'Longitude', number: true),
          CsvCol('description', 'Description'),
          CsvCol('trigger_radius_m', 'Trigger radius (m)', number: true),
        ],
        defaults: {'park_code': 'ocala'},
      ),
      const CsvTarget(
        label: 'Stories',
        table: 'stories',
        generatedIdColumn: 'story_id',
        columns: [
          CsvCol('title', 'Title', required: true),
          CsvCol('story_category', 'Category'),
          CsvCol('short_summary', 'Short summary'),
          CsvCol('full_story', 'Full story'),
          CsvCol('voice_script', 'Voice script'),
        ],
        // story_category is NOT NULL with no DB default → always provide one
        // (a mapped CSV value overrides this).
        defaults: {
          'destination_id': _ocalaDest,
          'published': true,
          'story_category': 'history',
        },
      ),
      const CsvTarget(
        label: 'Historical Events',
        table: 'historical_events',
        note: 'Requires a `historical_events` table.',
        columns: [
          CsvCol('title', 'Title', required: true),
          CsvCol('year', 'Year', number: true),
          CsvCol('description', 'Description'),
        ],
        defaults: {'destination_id': _ocalaDest},
      ),
      const CsvTarget(
        label: 'Campgrounds',
        table: 'campgrounds',
        note: 'Requires a `campgrounds` table.',
        columns: [
          CsvCol('name', 'Name', required: true),
          CsvCol('sites', 'Number of sites', number: true),
          CsvCol('latitude', 'Latitude', number: true),
          CsvCol('longitude', 'Longitude', number: true),
          CsvCol('description', 'Description'),
        ],
        defaults: {'destination_id': _ocalaDest},
      ),
      const CsvTarget(
        label: 'Songs (metadata only)',
        table: 'songs',
        columns: [
          CsvCol('title', 'Title', required: true),
          CsvCol('artist', 'Artist'),
          CsvCol('album', 'Album'),
          CsvCol('genre', 'Genre'),
          CsvCol('station', 'Station'),
          CsvCol('park_code', 'Park code'),
          CsvCol('audio_url', 'Audio URL'),
          CsvCol('cover_image', 'Cover image URL'),
          CsvCol('duration', 'Duration (seconds)', number: true),
        ],
        defaults: {'category': 'music', 'is_active': true},
      ),
    ];

/// Random v4 UUID for tables whose PK lacks a default (e.g. stories.story_id).
String uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).toList();
  return '${h.sublist(0, 4).join()}-${h.sublist(4, 6).join()}-'
      '${h.sublist(6, 8).join()}-${h.sublist(8, 10).join()}-'
      '${h.sublist(10, 16).join()}';
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Guess a CSV header for each DB column by normalized-name match. Returns a
/// map of DB column key -> CSV header (or null when no reasonable match).
Map<String, String?> autoMapColumns(List<String> headers, CsvTarget target) {
  final byNorm = {for (final h in headers) _norm(h): h};
  String? guess(CsvCol col) {
    final exact = byNorm[_norm(col.key)] ?? byNorm[_norm(col.label)];
    if (exact != null) return exact;
    for (final h in headers) {
      final nh = _norm(h);
      final nk = _norm(col.key);
      if (nh.isNotEmpty && (nh.contains(nk) || nk.contains(nh))) return h;
    }
    return null;
  }

  return {for (final col in target.columns) col.key: guess(col)};
}

/// Value of [header] in [row] (trimmed; null when empty/missing).
String? cellFor(List<String> headers, List<String> row, String? header) {
  if (header == null) return null;
  final i = headers.indexOf(header);
  if (i < 0 || i >= row.length) return null;
  final v = row[i].trim();
  return v.isEmpty ? null : v;
}

/// Builds the DB record for one CSV [row] using [mapping], or null when a
/// required field is missing (so the caller can count it as skipped).
Map<String, dynamic>? buildRecord(
  CsvTarget target,
  List<String> headers,
  List<String> row,
  Map<String, String?> mapping, {
  String Function()? uuid,
}) {
  final rec = <String, dynamic>{...target.defaults};
  for (final col in target.columns) {
    final v = cellFor(headers, row, mapping[col.key]);
    if (v == null) continue;
    rec[col.key] = col.number ? num.tryParse(v) : v;
  }
  for (final col in target.requiredColumns) {
    if (rec[col.key] == null || '${rec[col.key]}'.trim().isEmpty) return null;
  }
  if (target.generatedIdColumn != null) {
    rec[target.generatedIdColumn!] = (uuid ?? uuidV4)();
  }
  if (target.matchKeyFrom != null) {
    final base = cellFor(headers, row, mapping[target.matchKeyFrom!]);
    if (base != null) rec['match_key'] = normalizeMatchKey(base);
  }
  return rec;
}

/// True when every required column is mapped to a CSV header.
bool requiredMapped(CsvTarget target, Map<String, String?> mapping) =>
    target.requiredColumns.every((c) => mapping[c.key] != null);
