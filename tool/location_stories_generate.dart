// Builds the whole-journey narration library for a county: county-level stories
// (welcome, history, fun facts, nature, agriculture, economy, hidden gems) and,
// for every city already seeded in location_content, city stories (welcome,
// history, fun facts) + a community story. Written with OpenAI and inserted into
// location_content so the Location Intelligence Engine airs them by GPS. Voice
// afterward with tool/location_audio.dart.
//
// Usage:
//   OPENAI_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/location_stories_generate.dart --county Marion --state Florida \
//     [--limit-cities N] [--dry-run]
import 'dart:convert';
import 'dart:io';

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

const _countyTypes = {
  'county_welcome': 'a warm welcome as the driver enters the county',
  'county_history': 'a short, vivid history of the county',
  'county_fun_facts': 'a surprising fun fact about the county',
  'county_nature': 'the natural landscape, springs, forests and wildlife',
  'county_agriculture': 'the farming/agriculture the county is known for',
  'county_economy': 'what drives the local economy',
  'county_hidden_gems': 'a lesser-known local gem worth a stop',
};

const _cityTypes = {
  'city_welcome': 'a warm welcome as the driver enters the town',
  'city_history': 'a short history of the town',
  'city_fun_facts': 'a fun fact about the town',
  'community_story': 'the character and story of this community',
};

Future<Map<String, String>> _stories(HttpClient http, String apiKey,
    String model, String place, String county, String state,
    Map<String, String> types) async {
  final keys = types.keys.join(', ');
  final spec = types.entries.map((e) => '- ${e.key}: ${e.value}').join('\n');
  final sys = 'You are a warm, knowledgeable Florida travel-radio host. Write '
      'vivid, conversational 2-3 sentence spoken narrations (no lists, no '
      'placeholders). Return ONLY a JSON object with exactly these keys: $keys.';
  final user = 'Place: "$place" in $county County, $state.\n$spec';
  final req = await http
      .postUrl(Uri.parse('https://api.openai.com/v1/chat/completions'));
  req.headers.set('Authorization', 'Bearer $apiKey');
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode({
    'model': model,
    'temperature': 0.9,
    'response_format': {'type': 'json_object'},
    'messages': [
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': user},
    ],
  })));
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 300) {
    throw 'OpenAI ${res.statusCode}: ${body.substring(0, body.length.clamp(0, 200))}';
  }
  final content = jsonDecode(body)['choices'][0]['message']['content'] as String;
  final obj = jsonDecode(content) as Map<String, dynamic>;
  return {for (final k in types.keys) k: (obj[k] ?? '').toString().trim()};
}

Future<void> main(List<String> args) async {
  final county = _arg(args, 'county', 'Marion');
  final state = _arg(args, 'state', 'Florida');
  final model = _arg(args, 'model', 'gpt-4o-mini');
  final dryRun = args.contains('--dry-run');
  final limitCities = int.tryParse(_arg(args, 'limit-cities', '0')) ?? 0;

  final url = (Platform.environment['SUPABASE_URL'] ??
          'https://qqeyvhcgirmfokoftiuz.supabase.co')
      .replaceAll(RegExp(r'/$'), '');
  final key = Platform.environment['SUPABASE_SERVICE_KEY'] ??
      Platform.environment['SUPABASE_ANON_KEY'] ?? '';
  final openai = Platform.environment['OPENAI_API_KEY'] ?? '';
  if (key.isEmpty || (!dryRun && openai.isEmpty)) {
    stderr.writeln('Missing SUPABASE key and/or OPENAI_API_KEY.');
    exit(2);
  }

  final http = HttpClient();
  final sbh = {'apikey': key, 'Authorization': 'Bearer $key'};

  // Load existing county rows to find the cities and a centroid.
  final getReq = await http.getUrl(Uri.parse(
      '$url/rest/v1/location_content?select=title,category,latitude,longitude,city'
      '&county=eq.$county'));
  sbh.forEach(getReq.headers.set);
  final getRes = await getReq.close();
  final rows = (jsonDecode(await getRes.transform(utf8.decoder).join()) as List)
      .cast<Map<String, dynamic>>();
  if (rows.isEmpty) {
    stderr.writeln('No location_content for $county County. Seed it first '
        '(tool/location_content_seed.dart).');
    exit(1);
  }
  double avgLat = 0, avgLng = 0;
  for (final r in rows) {
    avgLat += (r['latitude'] as num).toDouble();
    avgLng += (r['longitude'] as num).toDouble();
  }
  avgLat /= rows.length;
  avgLng /= rows.length;

  final cities = rows
      .where((r) => (r['city'] ?? '').toString().isNotEmpty)
      .toList();
  final cityList = limitCities > 0 ? cities.take(limitCities).toList() : cities;
  stdout.writeln('$county County: ${cities.length} cities '
      '(processing ${cityList.length}), centroid ($avgLat, $avgLng)');

  final payload = <Map<String, dynamic>>[];
  Map<String, dynamic> mk(String title, String cat, num lat, num lng,
          String text, {String? city, int priority = 10}) =>
      {
        'title': title,
        'category': cat,
        'subcategory': null,
        'latitude': lat,
        'longitude': lng,
        'county': county,
        'city': city,
        'state': state,
        'park': null,
        'radius': null,
        'priority': priority,
        'estimated_duration': 90,
        'cooldown': 21600,
        'text': text,
        'audio_url': null,
        'destination_code': null,
      };

  // County library.
  if (dryRun) {
    stdout.writeln('  [dry] county library: ${_countyTypes.keys.join(", ")}');
  } else {
    final s = await _stories(http, openai, model, '$county County', county,
        state, _countyTypes);
    _countyTypes.forEach((cat, _) {
      final t = s[cat] ?? '';
      if (t.isNotEmpty) {
        payload.add(mk('$county County — ${cat.replaceAll("county_", "").replaceAll("_", " ")}',
            cat, avgLat, avgLng, t, priority: cat == 'county_welcome' ? 30 : 15));
      }
    });
    stdout.writeln('  ✓ county library (${_countyTypes.length})');
  }

  // City + community libraries.
  for (final c in cityList) {
    final name = (c['city'] ?? c['title']).toString();
    final lat = c['latitude'] as num;
    final lng = c['longitude'] as num;
    if (dryRun) {
      stdout.writeln('  [dry] $name: ${_cityTypes.keys.join(", ")}');
      continue;
    }
    try {
      final s = await _stories(http, openai, model, name, county, state, _cityTypes);
      _cityTypes.forEach((cat, _) {
        final t = s[cat] ?? '';
        if (t.isNotEmpty) {
          payload.add(mk('$name — ${cat.replaceAll("city_", "").replaceAll("_", " ")}',
              cat, lat, lng, t,
              city: name, priority: cat == 'city_welcome' ? 25 : 10));
        }
      });
      stdout.writeln('  ✓ $name (${_cityTypes.length})');
    } catch (e) {
      stderr.writeln('  ✗ $name: $e');
    }
  }

  stdout.writeln('rows to insert: ${payload.length}');
  if (dryRun || payload.isEmpty) {
    http.close(force: true);
    return;
  }

  // Insert in chunks (uniform keys).
  const chunk = 50;
  var inserted = 0;
  for (var i = 0; i < payload.length; i += chunk) {
    final batch = payload.sublist(i, (i + chunk).clamp(0, payload.length));
    final insReq = await http.postUrl(Uri.parse('$url/rest/v1/location_content'));
    sbh.forEach(insReq.headers.set);
    insReq.headers.set('Prefer', 'return=minimal');
    insReq.headers.contentType = ContentType.json;
    insReq.add(utf8.encode(jsonEncode(batch)));
    final insRes = await insReq.close();
    final b = await insRes.transform(utf8.decoder).join();
    if (insRes.statusCode >= 300) {
      stderr.writeln('insert ${insRes.statusCode}: $b');
    } else {
      inserted += batch.length;
    }
  }
  stdout.writeln('\n=== Done ===  inserted $inserted narration rows for '
      '$county County.');
  http.close(force: true);
}
