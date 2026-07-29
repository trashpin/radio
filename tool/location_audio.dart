// Voices location_content rows with ElevenLabs (optionally writing a short
// narration with OpenAI first), uploads the MP3 to voiceovers/locations/, and
// sets audio_url (+ the generated text). Scope with --county.
//
// Usage:
//   OPENAI_API_KEY=... ELEVENLABS_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/location_audio.dart --county Marion --voice kPzsL2i3teMYv0FxEYQ6 \
//     --voice-name "DJ Brittney" [--generate] [--limit N] [--dry-run]
import 'dart:convert';
import 'dart:io';

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

Future<String> _narrate(HttpClient http, String apiKey, String model,
    Map<String, dynamic> r) async {
  final title = (r['title'] ?? '').toString();
  final cat = (r['category'] ?? '').toString().replaceAll('_', ' ');
  final county = (r['county'] ?? '').toString();
  final state = (r['state'] ?? 'Florida').toString();
  final sys = 'You are a warm, knowledgeable local travel-radio host. Write a '
      'vivid, conversational 2-3 sentence narration to play as a driver passes '
      'this place. No placeholders, no lists, just natural speech.';
  final user = 'Place: "$title" ($cat) in $county County, $state.';
  final req = await http
      .postUrl(Uri.parse('https://api.openai.com/v1/chat/completions'));
  req.headers.set('Authorization', 'Bearer $apiKey');
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode({
    'model': model,
    'temperature': 0.9,
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
  return (jsonDecode(body)['choices'][0]['message']['content'] as String).trim();
}

Future<void> main(List<String> args) async {
  final county = _arg(args, 'county', 'Marion');
  final voiceId = _arg(args, 'voice', 'kPzsL2i3teMYv0FxEYQ6');
  final model = _arg(args, 'model', 'gpt-4o-mini');
  final generate = args.contains('--generate');
  final dryRun = args.contains('--dry-run');
  final limit = int.tryParse(_arg(args, 'limit', '0')) ?? 0;

  final url = (Platform.environment['SUPABASE_URL'] ??
          'https://qqeyvhcgirmfokoftiuz.supabase.co')
      .replaceAll(RegExp(r'/$'), '');
  final key = Platform.environment['SUPABASE_SERVICE_KEY'] ??
      Platform.environment['SUPABASE_ANON_KEY'] ?? '';
  final xi = Platform.environment['ELEVENLABS_API_KEY'] ?? '';
  final openai = Platform.environment['OPENAI_API_KEY'] ?? '';
  if (key.isEmpty || (!dryRun && xi.isEmpty)) {
    stderr.writeln('Missing SUPABASE key and/or ELEVENLABS_API_KEY.');
    exit(2);
  }

  final http = HttpClient();
  final sbh = {'apikey': key, 'Authorization': 'Bearer $key'};

  var filter = 'select=*&audio_url=is.null&county=eq.$county';
  if (limit > 0) filter += '&limit=$limit';
  final getReq = await http.getUrl(Uri.parse('$url/rest/v1/location_content?$filter'));
  sbh.forEach(getReq.headers.set);
  final getRes = await getReq.close();
  final body = await getRes.transform(utf8.decoder).join();
  if (getRes.statusCode >= 300) {
    stderr.writeln('load ${getRes.statusCode}: $body');
    exit(1);
  }
  final rows = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  stdout.writeln('$county location_content rows needing audio: ${rows.length}');

  var ok = 0, fail = 0;
  for (final r in rows) {
    final id = r['id'].toString();
    var text = (r['text'] ?? '').toString().trim();
    try {
      if (generate && openai.isNotEmpty) {
        text = await _narrate(http, openai, model, r);
      }
      if (text.isEmpty) text = '${r['title']}.';
      if (dryRun) {
        stdout.writeln('  [dry] ${r['title']}: "$text"');
        continue;
      }
      // ElevenLabs synth.
      final ttsReq = await http.postUrl(Uri.parse(
          'https://api.elevenlabs.io/v1/text-to-speech/$voiceId?output_format=mp3_44100_128'));
      ttsReq.headers.set('xi-api-key', xi);
      ttsReq.headers.set('accept', 'audio/mpeg');
      ttsReq.headers.contentType = ContentType.json;
      ttsReq.add(utf8.encode(
          jsonEncode({'text': text, 'model_id': 'eleven_multilingual_v2'})));
      final ttsRes = await ttsReq.close();
      if (ttsRes.statusCode >= 300) throw 'ElevenLabs ${ttsRes.statusCode}';
      final bytes = <int>[];
      await for (final c in ttsRes) {
        bytes.addAll(c);
      }
      // Upload.
      final path = 'locations/$id.mp3';
      final upReq = await http
          .postUrl(Uri.parse('$url/storage/v1/object/voiceovers/$path'));
      sbh.forEach(upReq.headers.set);
      upReq.headers.set('x-upsert', 'true');
      upReq.headers.contentType = ContentType('audio', 'mpeg');
      upReq.add(bytes);
      final upRes = await upReq.close();
      await upRes.drain<void>();
      if (upRes.statusCode >= 300) throw 'upload ${upRes.statusCode}';
      final publicUrl = '$url/storage/v1/object/public/voiceovers/$path';
      // Patch row.
      final patchReq = await http.openUrl(
          'PATCH', Uri.parse('$url/rest/v1/location_content?id=eq.$id'));
      sbh.forEach(patchReq.headers.set);
      patchReq.headers.set('Prefer', 'return=minimal');
      patchReq.headers.contentType = ContentType.json;
      patchReq.add(utf8.encode(jsonEncode({'audio_url': publicUrl, 'text': text})));
      final patchRes = await patchReq.close();
      await patchRes.drain<void>();
      if (patchRes.statusCode >= 300) throw 'update ${patchRes.statusCode}';
      ok++;
      stdout.writeln('  ✓ ${r['title']} (${(bytes.length / 1024).round()} KB)');
    } catch (e) {
      fail++;
      stderr.writeln('  ✗ ${r['title']}: $e');
    }
  }
  stdout.writeln('\n=== Done ===  voiced: $ok  failed: $fail');
  http.close(force: true);
}
