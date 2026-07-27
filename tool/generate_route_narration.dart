// Route narration generator: OpenAI -> route_narrations. Writes ranger-style
// driving narration for the leg between two destinations, grounded ONLY in
// ExplorerOS knowledge for both endpoints. Explorer Radio plays it en route.
//
// Run:
//   OPENAI_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/generate_route_narration.dart \
//     --from "Ocala National Forest" --to "Silver Springs State Park" [--dry-run]
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:explorer_os_mobile/features/narration/narration_qc.dart';

const _model = 'gpt-4o-mini';

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

double _miles(double lat1, double lng1, double lat2, double lng2) {
  const r = 3958.8; // earth radius, miles
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return r * 2 * math.asin(math.sqrt(h));
}

Future<void> main(List<String> args) async {
  final fromName = _arg(args, 'from', '');
  final toName = _arg(args, 'to', '');
  final dryRun = args.contains('--dry-run');
  if (fromName.isEmpty || toName.isEmpty) {
    stderr.writeln('Need --from "A" and --to "B".');
    exit(2);
  }

  final url = Platform.environment['SUPABASE_URL'] ??
      'https://qqeyvhcgirmfokoftiuz.supabase.co';
  final key = Platform.environment['SUPABASE_SERVICE_KEY'] ??
      Platform.environment['SUPABASE_ANON_KEY'] ??
      '';
  final openai = Platform.environment['OPENAI_API_KEY'] ?? '';
  if (key.isEmpty || (!dryRun && openai.isEmpty)) {
    stderr.writeln('Missing env: need SUPABASE_SERVICE_KEY (or SUPABASE_ANON_KEY)'
        ' and OPENAI_API_KEY.');
    exit(2);
  }

  final http = HttpClient();
  final sbh = {'apikey': key, 'Authorization': 'Bearer $key'};

  Future<List<Map<String, dynamic>>> get(String path) async {
    final r = await http.getUrl(Uri.parse('$url/rest/v1/$path'));
    sbh.forEach(r.headers.set);
    final res = await r.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) return const [];
    return (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> dest(String name) async {
    final rows = await get('destinations?name=eq.${Uri.encodeComponent(name)}'
        '&select=destination_id,description,destination_type,state_province,'
        'latitude,longitude&limit=1');
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> knowledge(String name, String? id) async {
    final facts = await get('knowledge_base?destination=eq.${Uri.encodeComponent(name)}'
        '&select=category,title,description&limit=30');
    final sb = StringBuffer();
    for (final f in facts) {
      sb.writeln('- [${f['category']}] ${f['title']}: ${f['description'] ?? ''}');
    }
    return sb.toString().trim();
  }

  try {
    final from = await dest(fromName);
    final to = await dest(toName);
    if (from == null || to == null) {
      throw 'destination not found: ${from == null ? fromName : toName}';
    }
    final fromId = from['destination_id']?.toString();
    final toId = to['destination_id']?.toString();
    final flat = (from['latitude'] as num?)?.toDouble();
    final flng = (from['longitude'] as num?)?.toDouble();
    final tlat = (to['latitude'] as num?)?.toDouble();
    final tlng = (to['longitude'] as num?)?.toDouble();
    final miles = (flat != null && flng != null && tlat != null && tlng != null)
        ? _miles(flat, flng, tlat, tlng)
        : null;
    final driveMin = miles == null ? null : (miles / 45 * 60).round(); // ~45 mph

    final kFrom = await knowledge(fromName, fromId);
    final kTo = await knowledge(toName, toId);

    stdout.writeln('Route "$fromName" -> "$toName"'
        '${miles != null ? '  (${miles.toStringAsFixed(1)} mi, ~${driveMin}min)' : ''}');

    final sys =
        'You are an experienced U.S. National Park ranger riding along with '
        'visitors, narrating the drive between two stops. Warm, friendly, '
        'natural, professional — never robotic, never mention being an AI. Tell '
        'a story that transitions from one place to the next: what they are '
        'leaving, the scenery, small towns, wildlife and landscape visible from '
        'the road, and a little history — then build anticipation for the next '
        'stop. Use ONLY the facts provided; do not invent specifics.';
    final user = 'Write ONE driving-narration script (~180 words, ~72s at 150 '
        'wpm) for the leg leaving "$fromName" and heading to "$toName"'
        '${miles != null ? ' (about ${miles.toStringAsFixed(0)} miles, '
            '~$driveMin minutes)' : ''}.\n\n'
        'Facts about "$fromName" (departure):\n${kFrom.isEmpty ? '(none)' : kFrom}\n\n'
        'Facts about "$toName" (destination):\n${kTo.isEmpty ? '(none)' : kTo}\n\n'
        'Return ONLY strict JSON: {"script":"..."}.';

    String script;
    if (dryRun) {
      script = '(dry run) Leaving $fromName, heading toward $toName…';
      stdout.writeln('[dry] would call OpenAI ($_model).');
    } else {
      final req = await http
          .postUrl(Uri.parse('https://api.openai.com/v1/chat/completions'));
      req.headers.set('Authorization', 'Bearer $openai');
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'model': _model,
        'temperature': 0.8,
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
      script = (jsonDecode(content)['script'] ?? '').toString();
      if (script.trim().isEmpty) throw 'empty script';
    }

    final words = wordCount(script);
    stdout.writeln('  script: $words words (~${formatSeconds(speakingSeconds(words))})');
    final snippet = script.length > 220 ? '${script.substring(0, 220)}…' : script;
    stdout.writeln('  $snippet');
    if (dryRun) return;

    final payload = {
      'from_destination_id': ?fromId,
      'to_destination_id': ?toId,
      'route_name': 'From $fromName to $toName',
      'distance': ?miles,
      'estimated_drive_time': ?driveMin,
      'script': script,
      'word_count': words,
      'status': 'review',
      'needs_review': kFrom.isEmpty && kTo.isEmpty,
      'ai_model': _model,
    };
    // Upsert on the (from,to,language) unique key.
    final ins = await http.postUrl(Uri.parse('$url/rest/v1/route_narrations'
        '?on_conflict=from_destination_id,to_destination_id,language'));
    sbh.forEach(ins.headers.set);
    ins.headers.set('Prefer', 'return=minimal,resolution=merge-duplicates');
    ins.headers.contentType = ContentType.json;
    ins.add(utf8.encode(jsonEncode(payload)));
    final insRes = await ins.close();
    final insBody = await insRes.transform(utf8.decoder).join();
    if (insRes.statusCode >= 300) throw 'insert ${insRes.statusCode}: $insBody';
    stdout.writeln('\n=== Done ===  saved route narration (status: review).');
  } catch (e) {
    stderr.writeln('FAILED: $e');
    exitCode = 1;
  } finally {
    http.close(force: true);
  }
}
