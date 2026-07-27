// Narration audio generator: voices approved destination_narrations rows with
// ElevenLabs, uploads the MP3 to the public `narration` bucket, and stores
// audio_url + voice + duration_seconds, then marks the row published.
//
// Run (after approving scripts in the Narration Studio):
//   ELEVENLABS_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/destination_narration_audio.dart \
//     [--id <narration_id>] [--voice-name "National Park Ranger"] \
//     [--voice <elevenlabs_voice_id>] [--limit 20] [--dry-run]
//
// Idempotent: rows that already have audio_url are skipped. Never regenerates
// unchanged audio (reuse existing files).
import 'dart:convert';
import 'dart:io';

import 'package:explorer_os_mobile/features/narration/narration_qc.dart';

const _bucket = 'narration';

// Suggested narrator voice -> ElevenLabs voice id (from assets/data/elevenlabs_voices.json).
const _voiceIds = <String, String>{
  'National Park Ranger': 'pNInz6obpgDQGcFmaJgB', // Adam (deep, authoritative)
  'Local Historian': 'pNInz6obpgDQGcFmaJgB',
  'Friendly Tour Guide': 'ErXwobaYiN019PkySvjV', // Antoni
  'Campfire Storyteller': 'TxGEqnHWrfWFTfGW9XjX', // Josh
  'Kids Adventure Guide': 'MF3mGyEYCl7XYWbV9V6O', // Elli (youthful)
  'Southern Storyteller': 'VR6AewLTigWG4xSOukaG', // Arnold
};
const _defaultVoiceName = 'National Park Ranger';
const _defaultVoiceId = 'pNInz6obpgDQGcFmaJgB';

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

Future<void> main(List<String> args) async {
  final oneId = _arg(args, 'id', '');
  final voiceName = _arg(args, 'voice-name', _defaultVoiceName);
  final voiceIdArg = _arg(args, 'voice', '');
  final limit = int.tryParse(_arg(args, 'limit', '20')) ?? 20;
  final dryRun = args.contains('--dry-run');

  final voiceId = voiceIdArg.isNotEmpty
      ? voiceIdArg
      : (_voiceIds[voiceName] ?? _defaultVoiceId);

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
    final filter = oneId.isNotEmpty
        ? 'id=eq.$oneId'
        : 'status=eq.approved&audio_url=is.null&script=not.is.null&order=created_at';
    final getReq = await http
        .getUrl(Uri.parse('$url/rest/v1/destination_narrations?select=*&$filter'));
    sbh.forEach(getReq.headers.set);
    final getRes = await getReq.close();
    final body = await getRes.transform(utf8.decoder).join();
    if (getRes.statusCode >= 300) throw 'load ${getRes.statusCode}: $body';
    var rows = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
    rows = rows.where((r) => (r['audio_url'] ?? '').toString().isEmpty).toList();
    if (limit > 0 && rows.length > limit) rows = rows.sublist(0, limit);
    stdout.writeln('narrations needing audio: ${rows.length}  '
        '(voice: $voiceName / $voiceId)');

    var ok = 0, fail = 0;
    for (final r in rows) {
      final id = r['id'].toString();
      final script = (r['script'] ?? '').toString();
      if (script.trim().isEmpty) continue;
      final words = (r['word_count'] as num?)?.toInt() ?? wordCount(script);
      final dur = (r['speaking_seconds'] as num?)?.toInt() ?? speakingSeconds(words);
      if (dryRun) {
        stdout.writeln('  [dry] ${r['script_type']} v${r['variant']}: '
            '$words words (~${formatSeconds(dur)}) -> voice $voiceId');
        continue;
      }
      try {
        final ttsReq = await http.postUrl(Uri.parse(
            'https://api.elevenlabs.io/v1/text-to-speech/$voiceId?output_format=mp3_44100_128'));
        ttsReq.headers.set('xi-api-key', xi);
        ttsReq.headers.set('accept', 'audio/mpeg');
        ttsReq.headers.contentType = ContentType.json;
        ttsReq.add(utf8.encode(
            jsonEncode({'text': script, 'model_id': 'eleven_multilingual_v2'})));
        final ttsRes = await ttsReq.close();
        if (ttsRes.statusCode >= 300) {
          final err = await ttsRes.transform(utf8.decoder).join();
          throw 'ElevenLabs ${ttsRes.statusCode}: '
              '${err.substring(0, err.length.clamp(0, 160))}';
        }
        final bytes = <int>[];
        await for (final c in ttsRes) {
          bytes.addAll(c);
        }
        final path = 'destinations/$id.mp3';
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
            'PATCH', Uri.parse('$url/rest/v1/destination_narrations?id=eq.$id'));
        sbh.forEach(patchReq.headers.set);
        patchReq.headers.set('Prefer', 'return=minimal');
        patchReq.headers.contentType = ContentType.json;
        patchReq.add(utf8.encode(jsonEncode({
          'audio_url': publicUrl,
          'voice': voiceName,
          'duration_seconds': dur,
          'status': 'published',
        })));
        final patchRes = await patchReq.close();
        await patchRes.drain<void>();
        if (patchRes.statusCode >= 300) throw 'update ${patchRes.statusCode}';
        ok++;
        stdout.writeln('  ✓ ${r['script_type']} v${r['variant']} '
            '(${(bytes.length / 1024).round()} KB)');
      } catch (e) {
        fail++;
        stderr.writeln('  ✗ ${r['script_type']} v${r['variant']}: $e');
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
