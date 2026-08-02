import 'dart:math';

import 'package:explorer_os_mobile/features/admin/image_match/filename_normalizer.dart';

/// One column expected by an import target.
class CsvCol {
  const CsvCol(
    this.key,
    this.label, {
    this.required = false,
    this.number = false,
  });
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
    this.passthrough = false,
    this.upsertKey,
    this.autoUuidColumn,
    this.autoSlugAndCode = false,
  });

  final String label;
  final String table;
  final List<CsvCol> columns;
  final Map<String, dynamic> defaults;

  /// Business key used to decide insert-vs-update (e.g. `destination_code`). When
  /// set, the importer looks the row up by this column: existing → update
  /// (preserving [autoUuidColumn]); missing → insert.
  final String? upsertKey;

  /// A UUID column that must never be null: if the CSV leaves it blank, the
  /// importer generates a UUID before inserting (e.g. `destination_id`). A
  /// supplied value is kept as-is.
  final String? autoUuidColumn;

  /// When true, blank `slug` and `destination_code` are generated from the row's
  /// `name`/`destination_type`/`state_province` so neither needs manual entry.
  final bool autoSlugAndCode;

  /// Direct-mapping mode: every CSV header is sent straight to the matching
  /// table column (by snake_cased header name) with no value validation and no
  /// column allow-list. Rows are not pre-filtered; the database validates them
  /// and any errors are reported per row. Used for the destinations importer.
  final bool passthrough;

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
    label: 'Master Locations',
    table: 'locations',
    note:
        'The single, county-agnostic locations table (migration 0031 + '
        '0038). Provide category as a type id (e.g. "spring", "museum", '
        '"restaurant"). id is generated automatically. Scalar fields only — '
        'images/audio/tags are managed in the editor.',
    columns: [
      CsvCol('name', 'Name', required: true),
      CsvCol('category', 'Category (type id)'),
      CsvCol('state', 'State'),
      CsvCol('county', 'County'),
      CsvCol('city', 'City'),
      CsvCol('community', 'Community'),
      CsvCol('latitude', 'Latitude', number: true),
      CsvCol('longitude', 'Longitude', number: true),
      CsvCol('trigger_radius', 'GPS trigger radius (m)', number: true),
      CsvCol('address', 'Street address'),
      CsvCol('short_description', 'Short description'),
      CsvCol('long_description', 'Long description'),
      CsvCol('description', 'Description (fallback)'),
      CsvCol('narration_script', 'Narration script'),
      CsvCol('external_website', 'External website'),
      CsvCol('hours', 'Hours'),
      CsvCol('admission', 'Admission / fees'),
      CsvCol('parking_info', 'Parking info'),
      CsvCol('restrooms', 'Restrooms'),
      CsvCol('difficulty', 'Difficulty'),
      CsvCol('priority', 'Priority', number: true),
    ],
    defaults: {'active': true, 'source': 'csv'},
  ),
  const CsvTarget(
    label: 'Destinations',
    table: 'destinations',
    passthrough: true,
    upsertKey: 'destination_code',
    autoUuidColumn: 'destination_id',
    autoSlugAndCode: true,
    note:
        'Direct import: every column maps straight to the destinations '
        'table by name (values sent as-is, e.g. "USA", "State Park"). '
        'destination_id is OPTIONAL — a UUID is generated automatically when '
        'blank. Rows are matched by destination_code: existing codes update '
        '(keeping their destination_id), new codes insert.',
    columns: [],
  ),
  const CsvTarget(
    label: 'Trails',
    table: 'trails',
    note: 'Run migration 0014 once to create this table.',
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
    note: 'Run migration 0014 (or 0009) once to create this table.',
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
    note: 'Run migration 0014 once to create this table.',
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
    note: 'Run migration 0014 once to create this table.',
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

bool _blank(dynamic v) => v == null || v.toString().trim().isEmpty;

/// Slugifies a name: lowercase, non-alphanumerics → hyphens, trimmed.
String slugifyName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// 2-letter USPS abbreviation for a state (fallback: first 2 letters).
String stateAbbrev(String? state) {
  const m = {
    'alabama': 'AL',
    'alaska': 'AK',
    'arizona': 'AZ',
    'arkansas': 'AR',
    'california': 'CA',
    'colorado': 'CO',
    'connecticut': 'CT',
    'delaware': 'DE',
    'florida': 'FL',
    'georgia': 'GA',
    'hawaii': 'HI',
    'idaho': 'ID',
    'illinois': 'IL',
    'indiana': 'IN',
    'iowa': 'IA',
    'kansas': 'KS',
    'kentucky': 'KY',
    'louisiana': 'LA',
    'maine': 'ME',
    'maryland': 'MD',
    'massachusetts': 'MA',
    'michigan': 'MI',
    'minnesota': 'MN',
    'mississippi': 'MS',
    'missouri': 'MO',
    'montana': 'MT',
    'nebraska': 'NE',
    'nevada': 'NV',
    'new hampshire': 'NH',
    'new jersey': 'NJ',
    'new mexico': 'NM',
    'new york': 'NY',
    'north carolina': 'NC',
    'north dakota': 'ND',
    'ohio': 'OH',
    'oklahoma': 'OK',
    'oregon': 'OR',
    'pennsylvania': 'PA',
    'rhode island': 'RI',
    'south carolina': 'SC',
    'south dakota': 'SD',
    'tennessee': 'TN',
    'texas': 'TX',
    'utah': 'UT',
    'vermont': 'VT',
    'virginia': 'VA',
    'washington': 'WA',
    'west virginia': 'WV',
    'wisconsin': 'WI',
    'wyoming': 'WY',
    'district of columbia': 'DC',
  };
  final s = (state ?? '').toLowerCase().trim();
  if (m.containsKey(s)) return m[s]!;
  final letters = s.replaceAll(RegExp(r'[^a-z]'), '').toUpperCase();
  return letters.isEmpty ? 'XX' : '${letters}XX'.substring(0, 2);
}

/// Short prefix for a destination type (matches the DB code family).
String destinationTypePrefix(String? type) {
  switch ((type ?? '').toLowerCase().trim()) {
    case 'national park':
      return 'NP';
    case 'national forest':
      return 'NF';
    case 'state park':
      return 'SP';
    case 'state forest':
      return 'SF';
    case 'spring':
    case 'springs':
      return 'SPR';
    case 'wildlife management area':
      return 'WMA';
    case 'scenic drive':
      return 'DRIVE';
    case 'historic site':
    case 'historical site':
      return 'HIST';
    case 'museum':
      return 'MUS';
    case 'city':
      return 'CITY';
    case 'beach':
      return 'BEACH';
    case 'campground':
      return 'CG';
    case 'trailhead':
      return 'TH';
    case 'business':
      return 'BIZ';
    default:
      return 'DEST';
  }
}

/// Deterministic scalable code, e.g. FLSP4821 — {state}{type}{4-digit hash of the
/// slug}. Deterministic on the name so re-importing the same row yields the same
/// code (keeps destination_code dedupe stable even when the CSV omits it).
String generateDestinationCode(String? name, String? type, String? state) {
  final base = stateAbbrev(state) + destinationTypePrefix(type);
  final slug = slugifyName(name ?? '');
  var h = 0;
  for (final c in slug.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return '$base${(h % 10000).toString().padLeft(4, '0')}';
}

/// Snake_cases a CSV header into a database column name, e.g.
/// "Destination Type" -> "destination_type", "State/Province" ->
/// "state_province". Used by passthrough (direct-mapping) targets.
String passthroughKey(String header) => header
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

/// Coerces a raw CSV cell into a JSON value: booleans and plain numbers where
/// unambiguous, otherwise the trimmed string. Empty -> null (so the column is
/// omitted and the DB default/null applies). No value validation is performed —
/// e.g. "USA" and "State Park" pass through untouched.
dynamic coerceCsvValue(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return null;
  final lower = v.toLowerCase();
  if (lower == 'true') return true;
  if (lower == 'false') return false;
  if (RegExp(r'^-?\d+$').hasMatch(v)) {
    final i = int.tryParse(v);
    if (i != null) return i;
  }
  if (RegExp(r'^-?\d*\.\d+$').hasMatch(v)) {
    final d = double.tryParse(v);
    if (d != null) return d;
  }
  return v;
}

/// Builds the DB record for one CSV [row] using [mapping], or null when a
/// required field is missing (so the caller can count it as skipped).
///
/// Passthrough targets map every CSV header directly to a table column and only
/// skip entirely-empty rows — validation is left to the database.
Map<String, dynamic>? buildRecord(
  CsvTarget target,
  List<String> headers,
  List<String> row,
  Map<String, String?> mapping, {
  String Function()? uuid,
}) {
  if (target.passthrough) {
    final rec = <String, dynamic>{...target.defaults};
    for (var i = 0; i < headers.length; i++) {
      final key = passthroughKey(headers[i]);
      if (key.isEmpty) continue;
      final val = coerceCsvValue(i < row.length ? row[i] : '');
      if (val == null) continue;
      rec[key] = val;
    }
    if (rec.isEmpty) return null;
    // Auto-fill slug + destination_code from the name when blank, so the admin
    // never has to type them (deterministic code keeps dedupe stable).
    if (target.autoSlugAndCode) {
      final name = (rec['name'] ?? '').toString();
      if (name.isNotEmpty) {
        if (_blank(rec['slug'])) rec['slug'] = slugifyName(name);
        if (_blank(rec['destination_code'])) {
          rec['destination_code'] = generateDestinationCode(
            name,
            rec['destination_type']?.toString(),
            rec['state_province']?.toString(),
          );
        }
      }
    }
    // Never send NULL for the auto-UUID column: generate one when blank, keep a
    // supplied value as-is. The admin never has to create UUIDs by hand.
    final idCol = target.autoUuidColumn;
    if (idCol != null && _blank(rec[idCol])) {
      rec[idCol] = (uuid ?? uuidV4)();
    }
    return rec;
  }
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

/// True when every required column is mapped to a CSV header. Passthrough
/// targets have no client-side required-mapping gate (the database validates).
bool requiredMapped(CsvTarget target, Map<String, String?> mapping) =>
    target.passthrough ||
    target.requiredColumns.every((c) => mapping[c.key] != null);
