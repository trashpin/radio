// Story audio generator: voices approved story_library rows with ElevenLabs,
// uploads to the public `narration` bucket, and marks them published.
//
// Run (after approving stories in Story Studio):
//   ELEVENLABS_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/story_audio.dart [--limit 10] [--dry-run]
//
// Only processes rows that are approved and have a transcript but no audio_url.
// Idempotent: existing audio is never regenerated.
import 'dart:convert';
import 'dart:io';

const _bucket = 'narration';
const _defaultVoiceId = '21m00Tcm4TlvDq8ikWAM'; // Rachel

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

Future<void> main(List<String> args) async {
  final limit = int.tryParse(_arg(args, 'limit', '0')) ?? 0;
  final dryRun = args.contains('--dry-run');

  final url = Platform.environment['SUPABASE_URL'] ??
      'https://qqeyvhcgirmfokoftiuz.supabase.co';
  final key = Platform.environment['SUPABASE_SERVICE_KEY'] ??
      Platform.environment['SUPABASE_ANON_KEY'] ??
      '';
  final xi = Platform.environment['ELEVENLABS_API_KEY'] ?? '';
  if (key.isEmpty || (!dryRun && xi.isEmpty)) {
    stderr.writeln('Missing env: need SUPABASE_SERVICE_KEY (or SUPABASE_ANON_KEY)'
        ' and ELEVENLABS_API_KEY.');
    exit(2);
  }

  final http = HttpClient();
  final sbh = {'apikey': key, 'Authorization': 'Bearer $key'};
  try {
    // Approved stories with a transcript but no audio yet.
    final getReq = await http.getUrl(Uri.parse('$url/rest/v1/story_library'
        '?select=*&approved=eq.true&audio_url=is.null&transcript=not.is.null'
        '&order=created_at'));
    sbh.forEach(getReq.headers.set);
    final getRes = await getReq.close();
    final body = await getRes.transform(utf8.decoder).join();
    if (getRes.statusCode >= 300) throw 'load ${getRes.statusCode}: $body';
    var rows = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
    if (limit > 0 && rows.length > limit) rows = rows.sublist(0, limit);
    stdout.writeln('approved stories needing audio: ${rows.length}');

    var ok = 0, fail = 0;
    for (final r in rows) {
      final id = r['id'].toString();
      final transcript = (r['transcript'] ?? '').toString();
      final voiceId = (r['voice_id'] ?? _defaultVoiceId).toString();
      if (transcript.trim().isEmpty) continue;
      if (dryRun) {
        stdout.writeln('  [dry] ${r['title']}: ${transcript.split(' ').length} words');
        continue;
      }
      try {
        final ttsReq = await http.postUrl(Uri.parse(
            'https://api.elevenlabs.io/v1/text-to-speech/$voiceId?output_format=mp3_44100_128'));
        ttsReq.headers.set('xi-api-key', xi);
        ttsReq.headers.set('accept', 'audio/mpeg');
        ttsReq.headers.contentType = ContentType.json;
        ttsReq.add(utf8.encode(
            jsonEncode({'text': transcript, 'model_id': 'eleven_multilingual_v2'})));
        final ttsRes = await ttsReq.close();
        if (ttsRes.statusCode >= 300) throw 'ElevenLabs ${ttsRes.statusCode}';
        final bytes = <int>[];
        await for (final c in ttsRes) {
          bytes.addAll(c);
        }
        final path = 'stories/$id.mp3';
        final upReq =
            await http.postUrl(Uri.parse('$url/storage/v1/object/$_bucket/$path'));
        sbh.forEach(upReq.headers.set);
        upReq.headers.set('x-upsert', 'true');
        upReq.headers.contentType = ContentType('audio', 'mpeg');
        upReq.add(bytes);
        final upRes = await upReq.close();
        await upRes.drain<void>();
        if (upRes.statusCode >= 300) throw 'upload ${upRes.statusCode}';
        final publicUrl = '$url/storage/v1/object/public/$_bucket/$path';

        final patchReq = await http.openUrl(
            'PATCH', Uri.parse('$url/rest/v1/story_library?id=eq.$id'));
        sbh.forEach(patchReq.headers.set);
        patchReq.headers.set('Prefer', 'return=minimal');
        patchReq.headers.contentType = ContentType.json;
        patchReq.add(utf8.encode(jsonEncode({
          'audio_url': publicUrl,
          'status': 'completed',
          'published': true,
        })));
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
    stdout.writeln('\n=== Done ===  voiced+published: $ok  failed: $fail');
  } catch (e) {
    stderr.writeln('FAILED: $e');
    exitCode = 1;
  } finally {
    http.close(force: true);
  }
}
