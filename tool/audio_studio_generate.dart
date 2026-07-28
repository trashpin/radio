// Audio Production Studio — batch narration generator.
//
// For every content record (species + map_locations) missing audio:
//   1. Generate a short narration script with OpenAI.
//   2. Synthesize it with ElevenLabs (default voice: DJ Brittney).
//   3. Upload the MP3 to the public `audio` Storage bucket (by category folder).
//   4. Insert an `audio_assets` row (status=complete).
//
// Run:
//   OPENAI_API_KEY=... ELEVENLABS_API_KEY=... \
//   SUPABASE_URL=... SUPABASE_SERVICE_KEY=... (or SUPABASE_ANON_KEY) \
//   dart run tool/audio_studio_generate.dart \
//     [--limit 10] [--category wildlife] [--voice kPzsL2i3teMYv0FxEYQ6] \
//     [--voice-name "DJ Brittney"] [--model gpt-4o-mini] [--dry-run]
//
// --dry-run generates + prints scripts via OpenAI only (no ElevenLabs, no
// upload, no DB write) — useful to validate wiring/cost before a full run.
// Idempotent: records that already have an `audio_assets` row are skipped.
import 'dart:convert';
import 'dart:io';

const _bucket = 'audio';
const _defaultVoiceId = 'kPzsL2i3teMYv0FxEYQ6'; // DJ Brittney
const _defaultVoiceName = 'DJ Brittney';
const _generationVersion = 1;

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

/// Maps a raw category token to a voice-category id + storage folder (mirrors
/// VoiceCategory.fromToken in the app).
({String id, String folder}) _voiceCategory(String? token) {
  final t = (token ?? '').toLowerCase();
  if (t.contains('bird')) return (id: 'birds', folder: 'birds');
  if (t.contains('fish')) return (id: 'fish', folder: 'fish');
  if (t.contains('reptile') || t.contains('amphib')) {
    return (id: 'reptiles', folder: 'reptiles');
  }
  if (t.contains('animal') || t.contains('mammal') || t.contains('wildlife')) {
    return (id: 'wildlife', folder: 'wildlife');
  }
  if (t.contains('plant') ||
      t.contains('tree') ||
      t.contains('flower') ||
      t.contains('wildflower')) {
    return (id: 'plants', folder: 'plants');
  }
  if (t.contains('historic') || t.contains('history')) {
    return (id: 'history', folder: 'history');
  }
  if (t.contains('story') || t.contains('stories')) {
    return (id: 'stories', folder: 'stories');
  }
  if (t.contains('safety')) return (id: 'safety', folder: 'safety');
  if (t.contains('radio')) return (id: 'radio', folder: 'radio');
  return (id: 'park_welcome', folder: 'parks');
}

class _Rec {
  _Rec(this.id, this.title, this.category, this.description);
  final String id;
  final String title;
  final String? category;
  final String? description;
}

Future<void> main(List<String> args) async {
  final limit = int.tryParse(_arg(args, 'limit', '10')) ?? 10;
  final categoryFilter = _arg(args, 'category', '').toLowerCase();
  final voiceId = _arg(args, 'voice', _defaultVoiceId);
  final voiceName = _arg(args, 'voice-name', _defaultVoiceName);
  final model = _arg(args, 'model', 'gpt-4o-mini');
  final dryRun = args.contains('--dry-run');

  final openai = Platform.environment['OPENAI_API_KEY'] ?? '';
  final xi = Platform.environment['ELEVENLABS_API_KEY'] ?? '';
  final url = (Platform.environment['SUPABASE_URL'] ?? '').isNotEmpty
      ? Platform.environment['SUPABASE_URL']!
      : 'https://qqeyvhcgirmfokoftiuz.supabase.co';
  final key = Platform.environment['SUPABASE_SERVICE_KEY'] ??
      Platform.environment['SUPABASE_ANON_KEY'] ??
      Platform.environment['SUPABASE_PUBLISHABLE_KEY'] ??
      '';

  if (openai.isEmpty) {
    stderr.writeln('Missing OPENAI_API_KEY.');
    exit(2);
  }
  if (!dryRun && xi.isEmpty) {
    stderr.writeln('Missing ELEVENLABS_API_KEY (required unless --dry-run).');
    exit(2);
  }
  if (!dryRun && key.isEmpty) {
    stderr.writeln('Missing SUPABASE service/anon key (required unless --dry-run).');
    exit(2);
  }

  final http = HttpClient();
  final sbh = {'apikey': key, 'Authorization': 'Bearer $key'};

  Future<List<Map<String, dynamic>>> get(String path) async {
    final req = await http.getUrl(Uri.parse('$url/rest/v1/$path'));
    sbh.forEach(req.headers.set);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) throw 'GET $path -> ${res.statusCode}: $body';
    return (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  }

  try {
    // 1) Records from species + map_locations.
    final records = <_Rec>[];
    if (key.isNotEmpty) {
      for (final r in await get('species?select=species_id,category,common_name,description&limit=5000')) {
        records.add(_Rec((r['species_id']).toString(),
            (r['common_name'] ?? '') as String, r['category'] as String?,
            r['description'] as String?));
      }
      for (final r in await get('map_locations?select=id,category,name,description&limit=5000')) {
        records.add(_Rec((r['id']).toString(), (r['name'] ?? '') as String,
            r['category'] as String?, r['description'] as String?));
      }
    }

    // 2) Skip records that already have audio.
    final existing = <String>{};
    if (key.isNotEmpty) {
      for (final r in await get('audio_assets?select=record_id&status=eq.complete&limit=100000')) {
        final rid = r['record_id']?.toString();
        if (rid != null) existing.add(rid);
      }
    }

    var todo = records.where((r) {
      if (r.title.trim().isEmpty) return false;
      if (existing.contains(r.id)) return false;
      if (categoryFilter.isNotEmpty &&
          !(r.category ?? '').toLowerCase().contains(categoryFilter)) {
        return false;
      }
      return true;
    }).toList();
    if (limit > 0 && todo.length > limit) todo = todo.sublist(0, limit);

    stdout.writeln('records needing audio: ${todo.length}  '
        '(voice: $voiceName / $voiceId, model: $model'
        '${dryRun ? ', DRY RUN' : ''})');

    var ok = 0, fail = 0;
    for (final rec in todo) {
      final vc = _voiceCategory(rec.category);
      try {
        // OpenAI: write the narration script.
        final script = await _writeScript(http, openai, model, rec);
        if (dryRun) {
          stdout.writeln('  [dry] ${rec.title} (${vc.id}): '
              '"${script.substring(0, script.length.clamp(0, 100))}…"');
          ok++;
          continue;
        }

        // ElevenLabs: synthesize.
        final bytes = await _tts(http, xi, voiceId, script);

        // Upload MP3.
        final path = '${vc.folder}/${rec.id}.mp3';
        final upReq = await http.postUrl(
            Uri.parse('$url/storage/v1/object/$_bucket/$path'));
        sbh.forEach(upReq.headers.set);
        upReq.headers.set('x-upsert', 'true');
        upReq.headers.contentType = ContentType('audio', 'mpeg');
        upReq.add(bytes);
        final upRes = await upReq.close();
        await upRes.drain<void>();
        if (upRes.statusCode >= 300) throw 'upload ${upRes.statusCode}';
        final publicUrl = '$url/storage/v1/object/public/$_bucket/$path';

        // Insert audio_assets row.
        final words = script.split(RegExp(r'\s+')).length;
        final insReq =
            await http.postUrl(Uri.parse('$url/rest/v1/audio_assets'));
        sbh.forEach(insReq.headers.set);
        insReq.headers.set('Prefer', 'return=minimal');
        insReq.headers.contentType = ContentType.json;
        insReq.add(utf8.encode(jsonEncode({
          'record_id': rec.id,
          'record_type': vc.id,
          'category': vc.id,
          'voice': voiceId,
          'voice_name': voiceName,
          'provider': 'elevenlabs',
          'language': 'en',
          'storage_path': path,
          'public_url': publicUrl,
          'duration': (words / 2.5).round(), // ~150 wpm
          'file_size': bytes.length,
          'generation_version': _generationVersion,
          'status': 'complete',
          'generated_at': DateTime.now().toUtc().toIso8601String(),
        })));
        final insRes = await insReq.close();
        await insRes.drain<void>();
        if (insRes.statusCode >= 300) throw 'insert ${insRes.statusCode}';

        ok++;
        stdout.writeln('  ✓ ${rec.title} (${vc.id}) '
            '${(bytes.length / 1024).round()} KB');
      } catch (e) {
        fail++;
        stderr.writeln('  ✗ ${rec.title}: $e');
      }
    }
    stdout.writeln('\n=== Done === generated: $ok  failed: $fail');
  } catch (e) {
    stderr.writeln('FAILED: $e');
    exitCode = 1;
  } finally {
    http.close(force: true);
  }
}

Future<String> _writeScript(
    HttpClient http, String apiKey, String model, _Rec rec) async {
  final sys = 'You are a warm, knowledgeable U.S. national/state park guide '
      'writing a short spoken narration (60-90 words) for the ExplorerOS '
      'in-park audio guide. Be vivid, accurate, and friendly. Output ONLY the '
      'narration text — no title, no quotes, no stage directions.';
  final user = 'Write the narration for: "${rec.title}"'
      '${rec.category != null ? ' (category: ${rec.category})' : ''}.'
      '${(rec.description ?? '').isNotEmpty ? ' Context: ${rec.description}' : ''}';

  final req = await http.postUrl(Uri.parse('https://api.openai.com/v1/chat/completions'));
  req.headers.set('Authorization', 'Bearer $apiKey');
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode({
    'model': model,
    'messages': [
      {'role': 'system', 'content': sys},
      {'role': 'user', 'content': user},
    ],
    'max_tokens': 220,
    'temperature': 0.8,
  })));
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 300) {
    throw 'OpenAI ${res.statusCode}: ${body.substring(0, body.length.clamp(0, 160))}';
  }
  final content = (jsonDecode(body)['choices'][0]['message']['content'] ?? '')
      .toString()
      .trim();
  if (content.isEmpty) throw 'OpenAI returned empty script';
  return content;
}

Future<List<int>> _tts(
    HttpClient http, String apiKey, String voiceId, String text) async {
  final req = await http.postUrl(Uri.parse(
      'https://api.elevenlabs.io/v1/text-to-speech/$voiceId?output_format=mp3_44100_128'));
  req.headers.set('xi-api-key', apiKey);
  req.headers.set('accept', 'audio/mpeg');
  req.headers.contentType = ContentType.json;
  req.add(utf8.encode(jsonEncode({'text': text, 'model_id': 'eleven_multilingual_v2'})));
  final res = await req.close();
  if (res.statusCode >= 300) {
    final err = await res.transform(utf8.decoder).join();
    throw 'ElevenLabs ${res.statusCode}: ${err.substring(0, err.length.clamp(0, 160))}';
  }
  final bytes = <int>[];
  await for (final c in res) {
    bytes.addAll(c);
  }
  return bytes;
}
