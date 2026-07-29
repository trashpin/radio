// Seeds `location_content` for a county from the geocoded `map_locations` table.
//
// Reads every map POI within the county bounding box, maps it into a
// location_content row (county/state stamped, category normalized, description
// carried as narration text), and inserts them — plus a synthesized county
// welcome so the Location Intelligence Engine fires a "Welcome to <County>".
//
// Usage:
//   SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/location_content_seed.dart --county Marion [--dry-run]
//
// Bounding boxes are defined below (Marion County, FL by default).
import 'dart:convert';
import 'dart:io';

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

/// County bounding boxes: [minLat, maxLat, minLng, maxLng] + centroid + state.
const _counties = <String, Map<String, dynamic>>{
  'Marion': {
    'bbox': [28.95, 29.45, -82.45, -81.60],
    'centroid': [29.187, -82.140],
    'state': 'Florida',
  },
};

String _mapCategory(String? c) {
  final n = (c ?? '').toLowerCase();
  if (n.contains('cities') || n.contains('city') || n.contains('town')) {
    return 'city_intro';
  }
  if (n.contains('spring') || n.contains('river') || n.contains('lake') ||
      n.contains('water')) {
    return 'water';
  }
  if (n.contains('historic')) return 'historic_landmark';
  if (n.contains('trail')) return 'trails';
  if (n.contains('wildlife')) return 'wildlife';
  if (n.contains('bird')) return 'birds';
  if (n.contains('plant') || n.contains('flora')) return 'plants';
  if (n.contains('camp')) return 'park';
  if (n.contains('scenic') || n.contains('overlook') || n.contains('vista')) {
    return 'scenic_overlook';
  }
  if (n.contains('museum')) return 'museum';
  if (n.contains('visitor')) return 'attraction';
  return 'attraction';
}

Future<void> main(List<String> args) async {
  final county = _arg(args, 'county', 'Marion');
  final dryRun = args.contains('--dry-run');
  final meta = _counties[county];
  if (meta == null) {
    stderr.writeln('Unknown county "$county". Known: ${_counties.keys.join(", ")}');
    exit(2);
  }
  final bbox = (meta['bbox'] as List).cast<num>();
  final centroid = (meta['centroid'] as List).cast<num>();
  final state = meta['state'] as String;

  final url = (Platform.environment['SUPABASE_URL'] ??
          'https://qqeyvhcgirmfokoftiuz.supabase.co')
      .replaceAll(RegExp(r'/$'), '');
  final key = Platform.environment['SUPABASE_SERVICE_KEY'] ??
      Platform.environment['SUPABASE_ANON_KEY'] ??
      '';
  if (key.isEmpty) {
    stderr.writeln('Missing SUPABASE_SERVICE_KEY / SUPABASE_ANON_KEY.');
    exit(2);
  }

  final http = HttpClient();
  final headers = {'apikey': key, 'Authorization': 'Bearer $key'};

  // 1) Pull map_locations within the county bbox.
  final filter =
      'select=*&latitude=gte.${bbox[0]}&latitude=lte.${bbox[1]}'
      '&longitude=gte.${bbox[2]}&longitude=lte.${bbox[3]}';
  final getReq = await http.getUrl(Uri.parse('$url/rest/v1/map_locations?$filter'));
  headers.forEach(getReq.headers.set);
  final getRes = await getReq.close();
  final body = await getRes.transform(utf8.decoder).join();
  if (getRes.statusCode >= 300) {
    stderr.writeln('load map_locations ${getRes.statusCode}: $body');
    exit(1);
  }
  final rows = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  stdout.writeln('$county County POIs found: ${rows.length}');

  // PostgREST bulk insert requires identical keys on every row.
  Map<String, dynamic> row({
    required String title,
    required String category,
    String? subcategory,
    required num latitude,
    required num longitude,
    String? city,
    String? park,
    num? radius,
    int priority = 0,
    int estimatedDuration = 120,
    String? text,
    String? audioUrl,
    String? destinationCode,
  }) =>
      {
        'title': title,
        'category': category,
        'subcategory': subcategory,
        'latitude': latitude,
        'longitude': longitude,
        'county': county,
        'city': city,
        'state': state,
        'park': park,
        'radius': radius,
        'priority': priority,
        'estimated_duration': estimatedDuration,
        'cooldown': 21600,
        'text': text,
        'audio_url': audioUrl,
        'destination_code': destinationCode,
      };

  final payload = <Map<String, dynamic>>[
    // Synthesized county welcome so entering the county triggers a narration.
    row(
      title: 'Welcome to $county County',
      category: 'county_history',
      latitude: centroid[0],
      longitude: centroid[1],
      priority: 20,
      estimatedDuration: 90,
      text: "You're now traveling through $county County, $state. "
          'Stay tuned as we explore the springs, forests, history, and '
          'wildlife all around you.',
    ),
  ];

  for (final r in rows) {
    final cat = _mapCategory(r['category'] as String?);
    final name = (r['name'] ?? '').toString();
    payload.add(row(
      title: name,
      category: cat,
      subcategory: r['subcategory'] as String?,
      latitude: r['latitude'] as num,
      longitude: r['longitude'] as num,
      city: cat == 'city_intro' ? name : null,
      radius: r['trigger_radius_m'] as num?,
      text: r['description'] as String?,
      audioUrl: r['audio_url'] as String?,
      destinationCode: r['park_code'] as String?,
    ));
  }

  stdout.writeln('rows to insert (incl. county welcome): ${payload.length}');
  for (final p in payload.take(8)) {
    stdout.writeln('  • [${p['category']}] ${p['title']}');
  }

  if (dryRun) {
    stdout.writeln('\n[dry-run] no rows written.');
    http.close(force: true);
    return;
  }

  // 2) Insert into location_content.
  final insReq = await http.postUrl(Uri.parse('$url/rest/v1/location_content'));
  headers.forEach(insReq.headers.set);
  insReq.headers.set('Prefer', 'return=minimal');
  insReq.headers.contentType = ContentType.json;
  insReq.add(utf8.encode(jsonEncode(payload)));
  final insRes = await insReq.close();
  final insBody = await insRes.transform(utf8.decoder).join();
  if (insRes.statusCode >= 300) {
    stderr.writeln('insert ${insRes.statusCode}: $insBody');
    if (insRes.statusCode == 404) {
      stderr.writeln('\n>> location_content does not exist yet. Apply migration '
          '0029_location_content.sql in the Supabase SQL editor first.');
    }
    exit(1);
  }
  stdout.writeln('\n=== Done ===  inserted ${payload.length} rows into '
      'location_content for $county County.');
  http.close(force: true);
}
