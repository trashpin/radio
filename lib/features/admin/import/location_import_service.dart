import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/admin/import/osm_overpass.dart';
import 'package:explorer_os_mobile/features/locations/data/location_repository.dart';
import 'package:explorer_os_mobile/features/locations/models/master_location.dart';

/// Outcome of an import run — surfaced in the admin console.
class ImportSummary {
  const ImportSummary({
    this.found = 0,
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.failed = 0,
    this.message,
  });
  final int found;
  final int inserted;
  final int updated;
  final int skipped;
  final int failed;
  final String? message;

  ImportSummary copyWith({
    int? found,
    int? inserted,
    int? updated,
    int? skipped,
    int? failed,
    String? message,
  }) =>
      ImportSummary(
        found: found ?? this.found,
        inserted: inserted ?? this.inserted,
        updated: updated ?? this.updated,
        skipped: skipped ?? this.skipped,
        failed: failed ?? this.failed,
        message: message ?? this.message,
      );

  @override
  String toString() =>
      'found $found · imported $inserted · updated $updated · '
      'skipped $skipped · failed $failed';
}

/// Imports locations from external sources into the ONE master `locations`
/// table, deduping on (source, source_id). Source-agnostic by design — today
/// it drives the OpenStreetMap/Overpass adapter; adding GNIS/NPS/etc. is just
/// another `import*` method that produces [MasterLocation]s the same way.
class LocationImportService {
  const LocationImportService(this._repo, {http.Client? client})
      : _client = client;

  final LocationRepository _repo;
  final http.Client? _client;

  /// Import every supported OSM feature inside a bounding box. [onlyMissing]
  /// skips rows that already exist; otherwise existing rows are updated
  /// (update-existing). [onLog] streams progress to the console.
  Future<ImportSummary> importOsmBoundingBox({
    required double south,
    required double west,
    required double north,
    required double east,
    String? state,
    String? county,
    bool onlyMissing = false,
    bool updateExisting = true,
    void Function(String)? onLog,
  }) async {
    if (!SupabaseService.isConfigured) {
      return const ImportSummary(message: 'Supabase not configured.');
    }
    final client = _client ?? http.Client();
    try {
      onLog?.call('Querying OpenStreetMap…');
      final q = OsmOverpass.query(
          south: south, west: west, north: north, east: east);
      final res = await client.post(
        Uri.parse(OsmOverpass.endpoint),
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
          // Overpass rejects UA-less requests with 406; identify politely.
          'User-Agent': 'ExplorerOS/1.0 (location import)',
        },
        body: {'data': q},
      );
      if (res.statusCode != 200) {
        return ImportSummary(
            message: 'Overpass error ${res.statusCode}. Try a smaller area.');
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final parsed =
          OsmOverpass.parse(json, state: state, county: county);
      onLog?.call('Found ${parsed.length} named features.');
      if (parsed.isEmpty) return const ImportSummary(found: 0);

      // Dedupe: which source_ids already exist (chunked to keep URLs sane).
      final ids = parsed.map((l) => l.sourceId!).toList();
      final existing = await _existingBySourceId(ids);

      var inserted = 0, updated = 0, skipped = 0, failed = 0;
      for (final loc in parsed) {
        final existingId = existing[loc.sourceId];
        try {
          if (existingId != null) {
            if (onlyMissing || !updateExisting) {
              skipped++;
              continue;
            }
            await _repo.update(existingId, _row(loc));
            updated++;
          } else {
            await _repo.create(_row(loc));
            inserted++;
          }
        } catch (_) {
          failed++;
        }
      }
      final summary = ImportSummary(
        found: parsed.length,
        inserted: inserted,
        updated: updated,
        skipped: skipped,
        failed: failed,
        message: 'Done.',
      );
      onLog?.call(summary.toString());
      return summary;
    } catch (e) {
      return ImportSummary(message: 'Import failed: $e');
    } finally {
      if (_client == null) client.close();
    }
  }

  /// Row for insert/update — model columns plus provenance (which `toWrite`
  /// intentionally omits).
  Map<String, dynamic> _row(MasterLocation l) => {
        ...l.toWrite(),
        'source': l.source,
        'source_id': l.sourceId,
      };

  /// Map of source_id → existing location id, for source='osm'. Chunks the
  /// `in` filter so a large area doesn't blow the URL length.
  Future<Map<String, String>> _existingBySourceId(List<String> ids) async {
    final out = <String, String>{};
    const chunk = 150;
    for (var i = 0; i < ids.length; i += chunk) {
      final slice = ids.sublist(i, (i + chunk).clamp(0, ids.length));
      try {
        final rows = await SupabaseService.client
            .from('locations')
            .select('id,source_id')
            .eq('source', OsmOverpass.source)
            .inFilter('source_id', slice) as List;
        for (final r in rows.cast<Map<String, dynamic>>()) {
          final sid = r['source_id'] as String?;
          final id = r['id'] as String?;
          if (sid != null && id != null) out[sid] = id;
        }
      } catch (_) {
        // Best-effort dedupe; on error we just risk re-inserting (the unique
        // (source, source_id) index — migration 0043 — is the backstop).
      }
    }
    return out;
  }
}

final locationImportServiceProvider = Provider<LocationImportService>(
  (ref) => LocationImportService(ref.watch(locationRepositoryProvider)),
);
