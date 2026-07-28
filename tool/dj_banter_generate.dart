// GPS-Aware DJ Banter generator: OpenAI -> Supabase `dj_banter`.
//
// Generates dozens of unique, conversational, GPS-aware DJ banter lines per
// category for a destination (target 20–50). Lines keep {placeholders} the
// runtime GpsBanterDirector fills live (e.g. {upcoming_attraction}, {county},
// {road}, {nearby_wildlife}, {nearby_spring}, {nearby_trail}) so the same clip
// still sounds specific to where the visitor actually is.
//
// Voicing is a separate step (ElevenLabs): tool/dj_audio.dart --from-dj-banter.
//
// Usage:
//   OPENAI_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/dj_banter_generate.dart --code OCALA --name "Ocala National Forest" \
//     --park "Ocala National Forest" --county "Marion County" --count 25
//
// Options:
//   --categories welcome,history_tease,...  (default: all 19)
//   --count 25            clips per category (default 20)
//   --model gpt-4o-mini   OpenAI model
//   --status published    inserted status (default: published)
//   --dry-run             print, don't insert
import 'dart:convert';
import 'dart:io';

import 'package:explorer_os_mobile/features/dj/banter_studio/banter_category.dart';

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

/// Per-category guidance so the DJ lines fit the moment and hint the transition.
String _guidance(BanterCategory c) {
  switch (c) {
    case BanterCategory.welcome:
      return 'warm on-air welcome as the visitor enters the area';
    case BanterCategory.arrival:
      return 'the visitor is pulling into an attraction right now';
    case BanterCategory.historyTease:
      return 'tease a history story that will play after the next song';
    case BanterCategory.wildlifeTease:
      return 'tease nearby wildlife the visitor might spot; story coming soon';
    case BanterCategory.plantTease:
      return 'tease interesting local plants/vegetation; story coming soon';
    case BanterCategory.birdTease:
      return 'tease local birds and where to listen for them';
    case BanterCategory.geologyTease:
      return 'tease the geology (springs, aquifer, formations); story coming';
    case BanterCategory.interestingFact:
      return 'a short surprising fact about the area';
    case BanterCategory.scenicObservation:
      return 'a casual observation about the current view/scenery';
    case BanterCategory.photoOpportunity:
      return 'point out a great photo opportunity nearby';
    case BanterCategory.trailSuggestion:
      return 'suggest a nearby trail worth stopping for';
    case BanterCategory.songIntro:
      return 'a brief lead-in to the next song';
    case BanterCategory.songOutro:
      return 'a brief wrap-up after a song, back-announcing the station';
    case BanterCategory.stationId:
      return 'a short station identification';
    case BanterCategory.promotion:
      return 'a light, non-salesy promo for the station/app';
    case BanterCategory.departure:
      return 'a friendly sign-off as the visitor leaves the area';
    case BanterCategory.hiddenGem:
      return 'reveal a lesser-known local gem';
    case BanterCategory.safetyReminder:
      return 'a brief, friendly safety reminder';
    case BanterCategory.familyActivity:
      return 'suggest a family-friendly activity nearby';
  }
}

Future<List<String>> _generate(
  HttpClient http,
  String apiKey,
  String model,
  BanterCategory category,
  int count, {
  required String name,
  required String park,
  required String county,
}) async {
  final placeholders = '{upcoming_attraction}, {park}, {county}, {road}, '
      '{nearby_wildlife}, {nearby_spring}, {nearby_river}, {nearby_lake}, '
      '{nearby_trail}, {nearby_historic_site}, {station}, {song_title}';
  final sys =
      'You are a warm, conversational travel-radio DJ riding along with a '
      'visitor through $name ($park) in $county, Florida. Write short spoken '
      'DJ lines that sound live and unscripted — never robotic. 1–2 sentences '
      'each. Where natural, use these placeholders EXACTLY (they are filled '
      'live from GPS): $placeholders. Do not invent specific place names for '
      'the placeholder slots — use the placeholder token instead. Vary openings '
      'so lines never sound repetitive.';
  final user =
      'Write $count DISTINCT DJ banter lines for the category "${category.label}" '
      '(${_guidance(category)}). Return ONLY a JSON array of strings.';

  final req = await http
      .postUrl(Uri.parse('https://api.openai.com/v1/chat/completions'));
  req.headers.set('Authorization', 'Bearer $apiKey');
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode({
    'model': model,
    'temperature': 1.0,
    'messages': [
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': user},
    ],
  })));
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 300) {
    throw 'OpenAI ${res.statusCode}: '
        '${body.substring(0, body.length.clamp(0, 300))}';
  }
  final content =
      jsonDecode(body)['choices'][0]['message']['content'] as String;
  return _parseLines(content);
}

/// Extracts string lines from an OpenAI response (JSON array, or fenced/loose).
List<String> _parseLines(String content) {
  var text = content.trim();
  // Strip code fences.
  text = text.replaceAll(RegExp(r'^```(json)?', multiLine: true), '').trim();
  final start = text.indexOf('[');
  final end = text.lastIndexOf(']');
  if (start >= 0 && end > start) {
    try {
      final arr = jsonDecode(text.substring(start, end + 1)) as List;
      return arr.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    } catch (_) {}
  }
  // Fallback: one line per row, stripping bullets/quotes.
  return text
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'^\s*[-*\d.]+\s*'), '').replaceAll('"', '').trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

Future<void> main(List<String> args) async {
  final code = _arg(args, 'code', '');
  final name = _arg(args, 'name', code);
  final park = _arg(args, 'park', name);
  final county = _arg(args, 'county', 'the county');
  final count = int.tryParse(_arg(args, 'count', '20')) ?? 20;
  final model = _arg(args, 'model', 'gpt-4o-mini');
  final status = _arg(args, 'status', 'published');
  final dryRun = args.contains('--dry-run');

  final categoriesArg = _arg(args, 'categories', '');
  final categories = categoriesArg.isEmpty
      ? BanterCategory.values
      : categoriesArg
          .split(',')
          .map((s) => BanterCategory.fromId(s.trim()))
          .whereType<BanterCategory>()
          .toList();

  if (code.isEmpty) {
    stderr.writeln('Missing --code <destination_code>.');
    exit(2);
  }

  final url = Platform.environment['SUPABASE_URL'] ??
      'https://qqeyvhcgirmfokoftiuz.supabase.co';
  final key = Platform.environment['SUPABASE_SERVICE_KEY'] ??
      Platform.environment['SUPABASE_ANON_KEY'] ??
      '';
  final openai = Platform.environment['OPENAI_API_KEY'] ?? '';
  if (!dryRun && (key.isEmpty || openai.isEmpty)) {
    stderr.writeln('Missing env: need SUPABASE_SERVICE_KEY (or SUPABASE_ANON_KEY)'
        ' and OPENAI_API_KEY.');
    exit(2);
  }

  final http = HttpClient();
  final sbh = {'apikey': key, 'Authorization': 'Bearer $key'};
  stdout.writeln('Generating banter for $name ($code) — '
      '${categories.length} categories × $count');

  var inserted = 0, failed = 0;
  try {
    for (final category in categories) {
      try {
        final lines = await _generate(http, openai, model, category, count,
            name: name, park: park, county: county);
        if (lines.isEmpty) {
          stderr.writeln('  ! ${category.label}: no lines');
          continue;
        }
        if (dryRun) {
          stdout.writeln('  [dry] ${category.label}: ${lines.length} lines');
          for (final l in lines.take(3)) {
            stdout.writeln('        • $l');
          }
          continue;
        }
        final payload = [
          for (final l in lines)
            {
              'destination_code': code,
              'category': category.id,
              'text': l,
              'gps_region': park,
              'status': status,
            }
        ];
        final insReq =
            await http.postUrl(Uri.parse('$url/rest/v1/dj_banter'));
        sbh.forEach(insReq.headers.set);
        insReq.headers.set('Prefer', 'return=minimal');
        insReq.headers.contentType = ContentType.json;
        insReq.add(utf8.encode(jsonEncode(payload)));
        final insRes = await insReq.close();
        final insBody = await insRes.transform(utf8.decoder).join();
        if (insRes.statusCode >= 300) {
          throw 'insert ${insRes.statusCode}: $insBody';
        }
        inserted += lines.length;
        stdout.writeln('  ✓ ${category.label}: ${lines.length} clips');
      } catch (e) {
        failed++;
        stderr.writeln('  ✗ ${category.label}: $e');
      }
    }
    stdout.writeln('\n=== Done ===  inserted: $inserted  category failures: $failed');
  } catch (e) {
    stderr.writeln('FAILED: $e');
    exitCode = 1;
  } finally {
    http.close(force: true);
  }
}
