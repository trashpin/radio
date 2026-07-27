// LLM story generator: OpenAI -> story_library (status "review").
//
// Generates research-based, interpreter-style narration scripts for a location
// with multiple distinct angles, and inserts them into story_library as drafts
// awaiting review. After approval, voice them with tool/story_audio.dart.
//
// Run:
//   OPENAI_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/story_generate.dart --location "Silver Glen Springs" \
//     --park "Ocala National Forest" --category SPRINGS --count 5 \
//     --lat 29.2461 --lng -81.6442 --radius 150 [--voice <id> --voice-name "DJ Brittney"] [--dry-run]
//
// --category accepts a StoryCategory dbValue (e.g. SPRINGS, WILDLIFE, PARK_HISTORY).
import 'dart:convert';
import 'dart:io';

import 'package:explorer_os_mobile/features/story_studio/models/story_category.dart';

const _model = 'gpt-4o-mini';

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

Future<void> main(List<String> args) async {
  final park = _arg(args, 'park', 'Ocala National Forest');
  final location = _arg(args, 'location', '');
  final categoryDb = _arg(args, 'category', 'PARK_HISTORY');
  final category = StoryCategory.fromDb(categoryDb);
  final count = int.tryParse(_arg(args, 'count', '5')) ?? 5;
  final audience = _arg(args, 'audience', 'general');
  final lat = double.tryParse(_arg(args, 'lat', ''));
  final lng = double.tryParse(_arg(args, 'lng', ''));
  final radius = int.tryParse(_arg(args, 'radius', '150')) ?? 150;
  final voiceId = _arg(args, 'voice', '');
  final voiceName = _arg(args, 'voice-name', '');
  final dryRun = args.contains('--dry-run');

  if (location.isEmpty) {
    stderr.writeln('Missing --location.');
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
  try {
    stdout.writeln('Generating $count "${category.label}" stories for '
        '"$location" ($park)…');

    // 1. Ask the LLM for distinct, research-based interpreter scripts.
    final sys =
        'You are an expert U.S. park interpreter who writes short, spoken-word '
        'audio narration scripts. They are accurate, use verifiable facts, and '
        'sound like a friendly ranger speaking to a visitor who has just arrived.';
    final user =
        'Write $count DISTINCT narration scripts for "$location" in "$park". '
        'Category: ${category.label}. Audience: $audience. '
        'Each script must be 90-140 words, take a DIFFERENT angle (history, '
        'wildlife, geology, family, photography, conservation, fun facts), and '
        'end warmly. Return ONLY strict JSON of the form '
        '{"stories":[{"title":"...","variation":"Historical",'
        '"transcript":"..."}]}.';

    List<dynamic> stories;
    if (dryRun) {
      stdout.writeln('[dry] would call OpenAI ($_model) with the prompt above.');
      stories = List.generate(
          count, (i) => {'title': '$location #$i', 'variation': 'Historical', 'transcript': '(dry run)'});
    } else {
      final req =
          await http.postUrl(Uri.parse('https://api.openai.com/v1/chat/completions'));
      req.headers.set('Authorization', 'Bearer $openai');
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'model': _model,
        'temperature': 0.85,
        'response_format': {'type': 'json_object'},
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
      stories = (jsonDecode(content)['stories'] as List?) ?? const [];
      if (stories.isEmpty) throw 'LLM returned no stories: $content';
    }
    stdout.writeln('LLM returned ${stories.length} stories.');

    if (dryRun) {
      for (final s in stories) {
        stdout.writeln('  [dry] ${s['title']} (${s['variation']})');
      }
      return;
    }

    // 2. Insert as review-status drafts.
    final sbh = {'apikey': key, 'Authorization': 'Bearer $key'};
    var ok = 0, fail = 0;
    for (final s in stories) {
      try {
        final payload = {
          'title': (s['title'] ?? location).toString(),
          'park_id': park,
          'location': location,
          'category': category.dbValue,
          'variation': (s['variation'] ?? '').toString(),
          'collection': location,
          'latitude': ?lat,
          'longitude': ?lng,
          'trigger_radius_m': radius,
          'transcript': (s['transcript'] ?? '').toString(),
          if (voiceId.isNotEmpty) 'voice_id': voiceId,
          if (voiceName.isNotEmpty) 'voice': voiceName,
          'audience': audience,
          'narration_style': 'ranger',
          'status': 'review',
          'created_by': 'llm:$_model',
        };
        final ins = await http.postUrl(Uri.parse('$url/rest/v1/story_library'));
        sbh.forEach(ins.headers.set);
        ins.headers.set('Prefer', 'return=minimal');
        ins.headers.contentType = ContentType.json;
        ins.add(utf8.encode(jsonEncode(payload)));
        final insRes = await ins.close();
        final insBody = await insRes.transform(utf8.decoder).join();
        if (insRes.statusCode >= 300) throw 'insert ${insRes.statusCode}: $insBody';
        ok++;
        stdout.writeln('  ✓ ${s['title']}');
      } catch (e) {
        fail++;
        stderr.writeln('  ✗ ${s['title']}: $e');
      }
    }
    stdout.writeln('\n=== Done ===  saved: $ok  failed: $fail  (status: review)');
    stdout.writeln('Next: approve in Story Studio, then voice with '
        'tool/story_audio.dart.');
  } catch (e) {
    stderr.writeln('FAILED: $e');
    exitCode = 1;
  } finally {
    http.close(force: true);
  }
}
