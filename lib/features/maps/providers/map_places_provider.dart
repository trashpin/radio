import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';
import 'package:explorer_os_mobile/features/maps/models/nearby_item.dart';

/// Always-on map "places" — Points of Interest (`map_locations`) and
/// `campgrounds` — plotted on the Google Map regardless of the search radius.
///
/// WHY THIS EXISTS: the "Around Me" system only surfaces `map_locations` within
/// a radius of the user, and campgrounds were never queried at all — so imported
/// POI/campgrounds produced no markers. These providers query BOTH tables, map
/// coordinates defensively (accepting latitude/longitude, lat/lng, lat/lon as
/// numbers or strings), skip invalid rows with a logged reason, and log counts
/// so the whole DB→map flow is traceable in the console.

double? _coord(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v is num) return v.toDouble();
    if (v is String) {
      final d = double.tryParse(v.trim());
      if (d != null) return d;
    }
  }
  return null;
}

const _latKeys = ['latitude', 'lat'];
const _lngKeys = ['longitude', 'lng', 'lon', 'long'];

/// Builds plottable [NearbyItem]s from raw table rows, logging returned/mapped/
/// skipped counts and per-row skip reasons.
List<NearbyItem> mapPlacesFromRows(
  List<Map<String, dynamic>> rows, {
  required String table,
  String? forcedCategory,
}) {
  final out = <NearbyItem>[];
  var skipped = 0;
  for (final r in rows) {
    final name =
        (r['name'] ?? r['title'] ?? r['common_name'] ?? '').toString().trim();
    final lat = _coord(r, _latKeys);
    final lng = _coord(r, _lngKeys);
    final label = name.isEmpty ? (r['id'] ?? '(no id)').toString() : name;

    if (lat == null || lng == null) {
      skipped++;
      debugPrint('[Map] $table SKIP "$label": no latitude/longitude '
          '(lat=$lat lng=$lng)');
      continue;
    }
    if (lat == 0 && lng == 0) {
      skipped++;
      debugPrint('[Map] $table SKIP "$label": coordinates are 0,0');
      continue;
    }
    if (lat.abs() > 90 || lng.abs() > 180) {
      skipped++;
      debugPrint('[Map] $table SKIP "$label": out-of-range '
          '(lat=$lat lng=$lng)');
      continue;
    }

    out.add(NearbyItem(
      id: '$table:${(r['id'] ?? r['location_id'] ?? r['campground_id'] ?? label)}',
      category: forcedCategory ?? (r['category'] as String?) ?? 'points_of_interest',
      name: name.isEmpty ? 'Unnamed' : name,
      latitude: lat,
      longitude: lng,
      subcategory: r['subcategory'] as String?,
      description: r['description'] as String?,
      imageUrl: (r['image_url'] ?? r['hero_image']) as String?,
      audioUrl: r['audio_url'] as String?,
      parkCode: r['park_code'] as String?,
    ));
  }
  debugPrint('[Map] $table: ${rows.length} returned, ${out.length} mapped, '
      '$skipped skipped');
  return out;
}

Future<List<NearbyItem>> _query(
  Ref ref,
  String table, {
  String? forcedCategory,
}) async {
  try {
    final rows = await SupabaseService.client.from(table).select() as List;
    return mapPlacesFromRows(
      rows.cast<Map<String, dynamic>>(),
      table: table,
      forcedCategory: forcedCategory,
    );
  } catch (e) {
    // Table missing / not reachable → no markers from it (logged, not fatal).
    debugPrint('[Map] $table query failed: $e');
    return const [];
  }
}

/// Points of Interest (the `map_locations` table).
final poiPlacesProvider = FutureProvider<List<NearbyItem>>(
    (ref) => _query(ref, 'map_locations'));

/// Campgrounds (forced to the `campgrounds` category so they get the cabin icon).
final campgroundPlacesProvider = FutureProvider<List<NearbyItem>>(
    (ref) => _query(ref, 'campgrounds', forcedCategory: 'campgrounds'));

/// All always-on places to plot (POI + campgrounds), merged.
final mapPlacesProvider = Provider<List<NearbyItem>>((ref) {
  final poi = ref.watch(poiPlacesProvider).value ?? const [];
  final camps = ref.watch(campgroundPlacesProvider).value ?? const [];
  final all = [...poi, ...camps];
  debugPrint('[Map] total places to plot: ${all.length} '
      '(points_of_interest=${poi.length}, campgrounds=${camps.length})');
  return all;
});
