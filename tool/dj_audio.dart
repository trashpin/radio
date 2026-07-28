// DJ banter audio generator: ElevenLabs -> Supabase Storage -> dj_banter_clips.
//
// Renders each banter template for a station+situation to audio in a specific
// DJ's ElevenLabs voice, uploads the MP3 to the public `voiceovers` bucket, and
// inserts a `dj_banter_clips` row. The radio then plays these clips between
// songs (in the DJ's voice), falling back to on-device TTS when none match.
//
// Run once per DJ/voice (repeat with different --station/--voice for each DJ):
//   ELEVENLABS_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/dj_audio.dart --station country --voice <id> --voice-name "Country Casey" --dj country_casey
//
// Options: --situations songOutro,stationId (default) | --dry-run | --force
// (--force clears existing clips for that station+situation first).
import 'dart:convert';
import 'dart:io';

import 'package:explorer_os_mobile/features/dj/banter/banter_engine.dart';

const _bucket = 'voiceovers';
const _defaultVoiceId = '21m00Tcm4TlvDq8ikWAM'; // Rachel

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

DjStation _stationFor(String s) => DjStation.values.firstWhere(
    (e) => e.name == s,
    orElse: () => DjStation.all);

BanterSituation? _situationFor(String s) {
  for (final e in BanterSituation.values) {
    if (e.name == s) return e;
  }
  return null;
}

/// Voices every radio_segments row that has a script but no audio, uploads the
/// MP3 to voiceovers/segments/, and marks the row published with its audio_url.
Future<void> _voiceSegments(HttpClient http, Map<String, String> sbh,
    String url, String xi, bool dryRun) async {
  final getReq = await http.getUrl(Uri.parse(
      '$url/rest/v1/radio_segments?select=*&audio_url=is.null&script=not.is.null'));
  sbh.forEach(getReq.headers.set);
  final getRes = await getReq.close();
  final body = await getRes.transform(utf8.decoder).join();
  if (getRes.statusCode >= 300) {
    stderr.writeln('load segments ${getRes.statusCode}: $body');
    return;
  }
  final rows = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  stdout.writeln('segments needing audio: ${rows.length}');
  var ok = 0, fail = 0;
  for (final r in rows) {
    final id = r['id'].toString();
    final script = (r['script'] ?? '').toString();
    final voiceId = (r['voice_id'] ?? _defaultVoiceId).toString();
    if (script.trim().isEmpty) continue;
    if (dryRun) {
      stdout.writeln('  [dry] ${r['title']}: "$script"');
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
        throw 'ElevenLabs ${ttsRes.statusCode}';
      }
      final bytes = <int>[];
      await for (final c in ttsRes) {
        bytes.addAll(c);
      }
      final path = 'segments/$id.mp3';
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
          'PATCH', Uri.parse('$url/rest/v1/radio_segments?id=eq.$id'));
      sbh.forEach(patchReq.headers.set);
      patchReq.headers.set('Prefer', 'return=minimal');
      patchReq.headers.contentType = ContentType.json;
      patchReq.add(utf8.encode(jsonEncode({
        'audio_url': publicUrl,
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
  stdout.writeln('\n=== Done (segments) ===  voiced: $ok  failed: $fail');
}

/// Voices every dj_banter row that has text but no audio (optionally scoped to
/// a destination code via --code), uploads the MP3 to voiceovers/banter/, and
/// sets audio_url + voice fields. Uses the row's voice_id when present, else the
/// --voice CLI value.
Future<void> _voiceDjBanter(HttpClient http, Map<String, String> sbh,
    String url, String xi, String fallbackVoiceId, String fallbackVoiceName,
    String? code, bool dryRun) async {
  var filter = 'select=*&audio_url=is.null&text=not.is.null';
  if (code != null && code.isNotEmpty) filter += '&destination_code=eq.$code';
  final getReq =
      await http.getUrl(Uri.parse('$url/rest/v1/dj_banter?$filter'));
  sbh.forEach(getReq.headers.set);
  final getRes = await getReq.close();
  final body = await getRes.transform(utf8.decoder).join();
  if (getRes.statusCode >= 300) {
    stderr.writeln('load dj_banter ${getRes.statusCode}: $body');
    return;
  }
  final rows = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  stdout.writeln('dj_banter rows needing audio: ${rows.length}');
  var ok = 0, fail = 0;
  for (final r in rows) {
    final id = r['id'].toString();
    final text = (r['text'] ?? '').toString();
    if (text.trim().isEmpty) continue;
    final voiceId = (r['voice_id'] ?? fallbackVoiceId).toString();
    final voiceName = (r['voice_name'] ?? fallbackVoiceName).toString();
    if (dryRun) {
      stdout.writeln('  [dry] ${r['category']}: "$text"');
      continue;
    }
    try {
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
      final path = 'banter/$id.mp3';
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
          'PATCH', Uri.parse('$url/rest/v1/dj_banter?id=eq.$id'));
      sbh.forEach(patchReq.headers.set);
      patchReq.headers.set('Prefer', 'return=minimal');
      patchReq.headers.contentType = ContentType.json;
      patchReq.add(utf8.encode(jsonEncode({
        'audio_url': publicUrl,
        'voice_id': voiceId,
        'voice_name': voiceName,
        'status': 'published',
      })));
      final patchRes = await patchReq.close();
      await patchRes.drain<void>();
      if (patchRes.statusCode >= 300) throw 'update ${patchRes.statusCode}';
      ok++;
      stdout.writeln('  ✓ ${r['category']} (${(bytes.length / 1024).round()} KB)');
    } catch (e) {
      fail++;
      stderr.writeln('  ✗ ${r['category']}: $e');
    }
  }
  stdout.writeln('\n=== Done (dj_banter) ===  voiced: $ok  failed: $fail');
}

Future<void> main(List<String> args) async {
  final stationName = _arg(args, 'station', 'all');
  final station = _stationFor(stationName);
  final voiceId = _arg(args, 'voice', _defaultVoiceId);
  final voiceName = _arg(args, 'voice-name', 'DJ');
  final djId = _arg(args, 'dj', station.name);
  final situations = _arg(args, 'situations', 'songOutro,stationId')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map(_situationFor)
      .whereType<BanterSituation>()
      .toList();
  final dryRun = args.contains('--dry-run');
  final force = args.contains('--force');

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

  // Generic context (no song-specific details) so clips are reusable.
  const ctx = BanterContext();
  final engine = BanterEngine();
  final http = HttpClient();
  final sbh = {'apikey': key, 'Authorization': 'Bearer $key'};

  // Mode 2: voice admin-authored Radio Automation library segments (rows in
  // radio_segments that have a script but no audio_url yet).
  if (args.contains('--from-segments')) {
    await _voiceSegments(http, sbh, url, xi, dryRun);
    http.close(force: true);
    return;
  }

  // Mode 3: voice GPS-aware DJ Banter Studio clips (dj_banter rows with text
  // but no audio_url). Scope with --code <destination_code>.
  if (args.contains('--from-dj-banter')) {
    final code = _arg(args, 'code', '');
    await _voiceDjBanter(http, sbh, url, xi, voiceId, voiceName,
        code.isEmpty ? null : code, dryRun);
    http.close(force: true);
    return;
  }

  stdout.writeln('DJ: $voiceName ($voiceId)  station: ${station.name}  '
      'situations: ${situations.map((s) => s.name).join(", ")}');

  var generated = 0, failed = 0;
  try {
    for (final situation in situations) {
      final templates = engine.templatesFor(station, situation);
      for (var i = 0; i < templates.length; i++) {
        final text = BanterEngine.fill(templates[i].text, ctx);
        final path = 'dj/${station.name}/${situation.name}_$i.mp3';
        if (dryRun) {
          stdout.writeln('  [dry] ${situation.name}[$i]: "$text" -> $_bucket/$path');
          continue;
        }
        try {
          // 1. Synthesize with the DJ's ElevenLabs voice.
          final ttsReq = await http.postUrl(Uri.parse(
              'https://api.elevenlabs.io/v1/text-to-speech/$voiceId?output_format=mp3_44100_128'));
          ttsReq.headers.set('xi-api-key', xi);
          ttsReq.headers.set('accept', 'audio/mpeg');
          ttsReq.headers.contentType = ContentType.json;
          ttsReq.add(utf8.encode(jsonEncode(
              {'text': text, 'model_id': 'eleven_multilingual_v2'})));
          final ttsRes = await ttsReq.close();
          if (ttsRes.statusCode >= 300) {
            final err = await ttsRes.transform(utf8.decoder).join();
            throw 'ElevenLabs ${ttsRes.statusCode}: '
                '${err.substring(0, err.length.clamp(0, 200))}';
          }
          final bytes = <int>[];
          await for (final chunk in ttsRes) {
            bytes.addAll(chunk);
          }

          // 2. Upload to Storage (upsert).
          final upReq = await http
              .postUrl(Uri.parse('$url/storage/v1/object/$_bucket/$path'));
          sbh.forEach(upReq.headers.set);
          upReq.headers.set('x-upsert', 'true');
          upReq.headers.contentType = ContentType('audio', 'mpeg');
          upReq.add(bytes);
          final upRes = await upReq.close();
          final upBody = await upRes.transform(utf8.decoder).join();
          if (upRes.statusCode >= 300) throw 'upload ${upRes.statusCode}: $upBody';
          final publicUrl = '$url/storage/v1/object/public/$_bucket/$path';

          // 3. Insert a dj_banter_clips row.
          final cReq = await http.postUrl(Uri.parse('$url/rest/v1/dj_banter_clips'));
          sbh.forEach(cReq.headers.set);
          cReq.headers.set('Prefer', 'return=minimal');
          cReq.headers.contentType = ContentType.json;
          cReq.add(utf8.encode(jsonEncode({
            'dj_id': djId,
            'voice_id': voiceId,
            'voice_name': voiceName,
            'station': station.name,
            'situation': situation.name,
            'text': text,
            'audio_url': publicUrl,
          })));
          final cRes = await cReq.close();
          final cBody = await cRes.transform(utf8.decoder).join();
          if (cRes.statusCode >= 300) throw 'clip insert ${cRes.statusCode}: $cBody';

          generated++;
          stdout.writeln('  ✓ ${situation.name}[$i] (${(bytes.length / 1024).round()} KB)');
        } catch (e) {
          failed++;
          stderr.writeln('  ✗ ${situation.name}[$i]: $e');
        }
      }
    }
    stdout.writeln('\n=== Done ===  generated: $generated  failed: $failed');
    if (force) {
      stdout.writeln('(note: --force de-dup not implemented; delete old rows in '
          'Supabase if regenerating)');
    }
  } catch (e) {
    stderr.writeln('FAILED: $e');
    exitCode = 1;
  } finally {
    http.close(force: true);
  }
}
