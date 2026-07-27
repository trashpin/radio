// Backfills `map_locations.category` with a Map Editor legend category inferred
// from each row's name/category, so the map's category-colored pins light up.
//
// Uses the SAME pure inference as the app (marker_category_infer.dart), so the
// data and the live markers stay consistent.
//
// Run:
//   SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/categorize_map_locations.dart [--dry-run] [--force]
//
// --dry-run: print the planned changes without writing.
// --force:   also re-categorize rows that already have a legend category.
import 'dart:convert';
import 'dart:io';

import 'package:explorer_os_mobile/features/maps/marker_category_infer.dart';

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final force = args.contains('--force');

  final url = Platform.environment['SUPABASE_URL'] ??
      'https://qqeyvhcgirmfokoftiuz.supabase.co';
  final key = Platform.environment['SUPABASE_SERVICE_KEY'] ??
      Platform.environment['SUPABASE_ANON_KEY'] ??
      '';
  if (key.isEmpty) {
    stderr.writeln('Missing env: SUPABASE_SERVICE_KEY (or SUPABASE_ANON_KEY).');
    exit(2);
  }

  final http = HttpClient();
  final headers = {'apikey': key, 'Authorization': 'Bearer $key'};

  final getReq = await http.getUrl(Uri.parse(
      '$url/rest/v1/map_locations?select=id,name,category,subcategory'));
  headers.forEach(getReq.headers.set);
  final getResp = await getReq.close();
  final body = await getResp.transform(utf8.decoder).join();
  if (getResp.statusCode != 200) {
    stderr.writeln('Fetch failed (${getResp.statusCode}): $body');
    exit(1);
  }
  final rows = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  stdout.writeln('map_locations: ${rows.length} rows');

  final counts = <String, int>{};
  var changed = 0;
  for (final r in rows) {
    final id = r['id']?.toString();
    if (id == null) continue;
    final current = (r['category'] as String?)?.trim();
    final key = inferCategoryKey(current, r['name'] as String?, r['subcategory'] as String?);
    counts[key] = (counts[key] ?? 0) + 1;

    // Skip rows already set to a legend category unless --force.
    final alreadyLegend = current != null && markerCategoryKeys.contains(current);
    if (current == key || (alreadyLegend && !force)) continue;

    changed++;
    stdout.writeln('  ${dryRun ? '[dry] ' : ''}$key  <=  '
        '"${r['name']}" (was: ${current ?? 'null'})');
    if (dryRun) continue;

    final patch = await http.openUrl(
        'PATCH', Uri.parse('$url/rest/v1/map_locations?id=eq.$id'));
    headers.forEach(patch.headers.set);
    patch.headers.set('Prefer', 'return=minimal');
    patch.headers.contentType = ContentType.json;
    patch.add(utf8.encode(jsonEncode({'category': key})));
    final pr = await patch.close();
    await pr.drain<void>();
    if (pr.statusCode >= 300) {
      stderr.writeln('  ! update failed for $id (${pr.statusCode})');
    }
  }

  stdout.writeln('\nDistribution: $counts');
  stdout.writeln('${dryRun ? 'Would change' : 'Changed'} $changed row(s).');
  http.close();
}
