// Pure helpers + registries for the Database Tools admin center.

/// A browsable table (Supabase/Postgres) exposed in the Tables/Export tools.
class DbTable {
  const DbTable(this.name, this.label, {this.group = 'Content'});
  final String name;
  final String label;
  final String group;
}

/// The tables the admin can browse/export/count. (Only app tables — never the
/// internal `auth`/`storage` schemas.)
const List<DbTable> kDbTables = [
  DbTable('destinations', 'Destinations', group: 'Core'),
  DbTable('species', 'Species', group: 'Nature'),
  DbTable('media', 'Media', group: 'Assets'),
  DbTable('songs', 'Songs', group: 'Audio'),
  DbTable('stories', 'Stories (legacy)', group: 'Content'),
  DbTable('story_library', 'Story Library', group: 'Content'),
  DbTable('knowledge_base', 'Knowledge Base', group: 'Content'),
  DbTable('generation_jobs', 'Generation Jobs', group: 'Content'),
  DbTable('radio_segments', 'Radio Segments', group: 'Audio'),
  DbTable('radio_schedule_rules', 'Schedule Rules', group: 'Audio'),
  DbTable('dj_banter_clips', 'DJ Clips', group: 'Audio'),
  DbTable('map_locations', 'Map Locations (POI)', group: 'Map'),
  DbTable('campgrounds', 'Campgrounds', group: 'Map'),
  DbTable('trails', 'Trails', group: 'Map'),
  DbTable('wildlife_alerts', 'Wildlife Alerts', group: 'Audio'),
  DbTable('safety_messages', 'Safety Messages', group: 'Audio'),
];

/// Which tables to surface as headline counts on the dashboard.
const List<DbTable> kDashboardTables = [
  DbTable('destinations', 'Destinations'),
  DbTable('species', 'Species'),
  DbTable('story_library', 'Stories'),
  DbTable('knowledge_base', 'Knowledge Records'),
  DbTable('songs', 'Songs'),
  DbTable('media', 'Audio/Media'),
  DbTable('map_locations', 'GPS Zones'),
  DbTable('generation_jobs', 'Jobs'),
];

/// How a maintenance script reads/changes data. Reads are safe; writes prompt
/// for confirmation.
enum MaintenanceKind { check, fix }

/// The filter operator a maintenance script uses.
enum FilterOp { isNull, eq }

/// A one-click maintenance operation, expressed as typed (PostgREST-safe)
/// filters — no raw SQL. Matches rows where [column] [op] [value].
class MaintenanceScript {
  const MaintenanceScript({
    required this.id,
    required this.label,
    required this.description,
    required this.table,
    required this.column,
    this.op = FilterOp.isNull,
    this.value,
    this.kind = MaintenanceKind.check,
    this.update,
  });

  final String id;
  final String label;
  final String description;
  final String table;
  final String column;
  final FilterOp op;
  final dynamic value;
  final MaintenanceKind kind;

  /// For [MaintenanceKind.fix]: the column→value update to apply to matches.
  final Map<String, dynamic>? update;

  bool get isDestructive => kind == MaintenanceKind.fix;
}

/// Built-in maintenance / saved scripts (all PostgREST-safe).
const List<MaintenanceScript> kMaintenanceScripts = [
  MaintenanceScript(
    id: 'stories_missing_audio',
    label: 'Find stories missing audio',
    description: 'Stories that have no audio_url yet.',
    table: 'story_library',
    column: 'audio_url',
  ),
  MaintenanceScript(
    id: 'stories_missing_gps',
    label: 'Find stories missing GPS',
    description: 'Stories with no latitude — they can never GPS-trigger.',
    table: 'story_library',
    column: 'latitude',
  ),
  MaintenanceScript(
    id: 'segments_missing_audio',
    label: 'Find radio segments missing audio',
    description: 'Radio segments with a script but no voiced audio.',
    table: 'radio_segments',
    column: 'audio_url',
  ),
  MaintenanceScript(
    id: 'facts_unapproved',
    label: 'Find unapproved knowledge facts',
    description: 'Researched facts still awaiting review.',
    table: 'knowledge_base',
    column: 'approved',
    op: FilterOp.eq,
    value: false,
  ),
  MaintenanceScript(
    id: 'jobs_failed',
    label: 'Find failed jobs',
    description: 'Generation jobs that failed.',
    table: 'generation_jobs',
    column: 'status',
    op: FilterOp.eq,
    value: 'failed',
  ),
  MaintenanceScript(
    id: 'species_missing_image',
    label: 'Find species missing photos',
    description: 'Species with no hero_image.',
    table: 'species',
    column: 'hero_image',
  ),
  MaintenanceScript(
    id: 'reset_failed_jobs',
    label: 'Reset failed jobs → pending',
    description: 'Re-queue every failed generation job so the tools retry it.',
    table: 'generation_jobs',
    column: 'status',
    op: FilterOp.eq,
    value: 'failed',
    kind: MaintenanceKind.fix,
    update: {'status': 'pending', 'message': null},
  ),
];

/// Encodes a list of row maps as CSV (RFC-4180 quoting). Columns are the union
/// of keys across rows, in first-seen order.
String csvEncode(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return '';
  final cols = <String>[];
  for (final r in rows) {
    for (final k in r.keys) {
      if (!cols.contains(k)) cols.add(k);
    }
  }
  String cell(dynamic v) {
    final s = v == null ? '' : '$v';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  final buf = StringBuffer()..writeln(cols.map(cell).join(','));
  for (final r in rows) {
    buf.writeln(cols.map((c) => cell(r[c])).join(','));
  }
  return buf.toString().trimRight();
}
