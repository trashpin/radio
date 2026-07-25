// Narration audio generator: ElevenLabs -> Supabase Storage -> media row.
//
// For each species in a park it composes a narration script (the same
// deterministic composer the app/admin use), synthesizes an MP3 with
// ElevenLabs, uploads it to Storage organized by park/category, and links it
// via a `media` audio row (media.species_id). The app then streams that file
// instantly on the species detail screen — no AI at runtime.
//
// Run:
//   ELEVENLABS_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/narration_audio.dart --park ocala [--limit 5] [--voice <id>] [--dry-run] [--force]
//
// Idempotent: skips species that already have narration audio unless --force.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:explorer_os_mobile/features/admin/image_match/filename_normalizer.dart';
import 'package:explorer_os_mobile/features/discovery/models/species.dart';
import 'package:explorer_os_mobile/features/narration/services/narration_script_composer.dart';

const _composer = NarrationScriptComposer();
const _bucket = 'narration';
// ElevenLabs "Rachel" — a stable default voice.
const _defaultVoiceId = '21m00Tcm4TlvDq8ikWAM';

/// Random v4 UUID (the `media` table's PK has no DB default).
String _uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).toList();
  return '${h.sublist(0, 4).join()}-${h.sublist(4, 6).join()}-'
      '${h.sublist(6, 8).join()}-${h.sublist(8, 10).join()}-'
      '${h.sublist(10, 16).join()}';
}

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

Future<void> main(List<String> args) async {
  final parkCode = _arg(args, 'park', 'ocala');
  final limit = int.tryParse(_arg(args, 'limit', '0')) ?? 0; // 0 = all
  var voiceId = _arg(args, 'voice', _defaultVoiceId);
  var voiceName = _arg(args, 'voice-name', 'Rachel');
  final voiceExplicit = args.contains('--voice');
  final category = _arg(args, 'category', ''); // filter species by category
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

  final http = HttpClient();
  final sbh = {'apikey': key, 'Authorization': 'Bearer $key'};

  Future<dynamic> getJson(String u) async {
    final req = await http.getUrl(Uri.parse(u));
    sbh.forEach(req.headers.set);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) throw 'GET $u -> ${res.statusCode}: $body';
    return body.isEmpty ? null : jsonDecode(body);
  }

  try {
    // Resolve destination.
    final destOverride = _arg(args, 'destination-id', '');
    String destId;
    if (destOverride.isNotEmpty) {
      destId = destOverride;
    } else {
      final dests = await getJson(
              '$url/rest/v1/destinations?select=destination_id,name&name=ilike.*$parkCode*')
          as List;
      if (dests.isEmpty) throw 'No Supabase destination matches "$parkCode".';
      destId = dests.first['destination_id'].toString();
    }
    stdout.writeln('destination_id: $destId');

    // Ensure the public storage bucket exists.
    if (!dryRun) {
      final createReq =
          await http.postUrl(Uri.parse('$url/storage/v1/bucket'));
      sbh.forEach(createReq.headers.set);
      createReq.headers.contentType = ContentType.json;
      createReq.add(utf8.encode(jsonEncode(
          {'id': _bucket, 'name': _bucket, 'public': true})));
      final cRes = await createReq.close();
      await cRes.drain<void>();
      stdout.writeln('bucket "$_bucket": ${cRes.statusCode == 200 ? 'created' : 'exists/ok (${cRes.statusCode})'}');
    }

    // Resolve the category's assigned default voice (unless --voice was given).
    if (!voiceExplicit && category.isNotEmpty) {
      try {
        final va = await getJson(
            '$url/rest/v1/voice_assignments?category=eq.$category&select=default_voice_name,default_voice_id') as List;
        if (va.isNotEmpty && va.first['default_voice_id'] != null) {
          voiceId = va.first['default_voice_id'].toString();
          voiceName = (va.first['default_voice_name'] ?? voiceName).toString();
          stdout.writeln('using assigned voice for "$category": $voiceName ($voiceId)');
        }
      } catch (_) {/* voice_assignments table not present — use default */}
    }

    // Load species for this park (optionally filtered by category).
    var q = '$url/rest/v1/species?select=*&destination_id=eq.$destId';
    if (category.isNotEmpty) q += '&category=eq.$category';
    final rows = await getJson('$q&order=common_name') as List;
    var species = rows.map((r) => Species.fromJson(r)).toList();
    if (limit > 0 && species.length > limit) species = species.sublist(0, limit);
    stdout.writeln('species to process: ${species.length}'
        '${category.isNotEmpty ? ' (category=$category)' : ''}');

    var generated = 0, skipped = 0, failed = 0;
    for (final s in species) {
      // Skip if narration audio already linked (unless --force).
      final existing = await getJson(
              '$url/rest/v1/media?select=media_id&species_id=eq.${s.id}&media_type=eq.audio')
          as List;
      if (existing.isNotEmpty && !force) {
        skipped++;
        continue;
      }

      final script = _composer.composeForSpecies(s);
      final path =
          'parks/$parkCode/${normalizeMatchKey(s.category)}/${normalizeMatchKey(s.commonName)}.mp3';

      if (dryRun) {
        stdout.writeln('  [dry] ${s.commonName}: ${_composer.wordCount(script)} words -> $_bucket/$path');
        continue;
      }

      try {
        // 1. Synthesize MP3 with ElevenLabs.
        final ttsReq = await http.postUrl(Uri.parse(
            'https://api.elevenlabs.io/v1/text-to-speech/$voiceId?output_format=mp3_44100_128'));
        ttsReq.headers.set('xi-api-key', xi);
        ttsReq.headers.set('accept', 'audio/mpeg');
        ttsReq.headers.contentType = ContentType.json;
        ttsReq.add(utf8.encode(jsonEncode({
          'text': script,
          'model_id': 'eleven_multilingual_v2',
        })));
        final ttsRes = await ttsReq.close();
        if (ttsRes.statusCode >= 300) {
          final err = await ttsRes.transform(utf8.decoder).join();
          throw 'ElevenLabs ${ttsRes.statusCode}: ${err.substring(0, err.length.clamp(0, 200))}';
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
        if (upRes.statusCode >= 300) {
          throw 'upload ${upRes.statusCode}: $upBody';
        }
        final publicUrl = '$url/storage/v1/object/public/$_bucket/$path';

        // 3. Link a media audio row (upsert-ish: delete old then insert).
        if (force && existing.isNotEmpty) {
          final delReq = await http.openUrl('DELETE',
              Uri.parse('$url/rest/v1/media?species_id=eq.${s.id}&media_type=eq.audio'));
          sbh.forEach(delReq.headers.set);
          await (await delReq.close()).drain<void>();
        }
        final mReq = await http.postUrl(Uri.parse('$url/rest/v1/media'));
        sbh.forEach(mReq.headers.set);
        mReq.headers.set('Prefer', 'return=minimal');
        mReq.headers.contentType = ContentType.json;
        mReq.add(utf8.encode(jsonEncode({
          'media_id': _uuidV4(),
          'species_id': s.id,
          'destination_id': destId,
          'media_type': 'audio',
          'title': '${s.commonName} narration',
          'file_url': publicUrl,
          'published': true,
        })));
        final mRes = await mReq.close();
        final mBody = await mRes.transform(utf8.decoder).join();
        if (mRes.statusCode >= 300) throw 'media insert ${mRes.statusCode}: $mBody';

        // Best-effort: also record the narration (with voice + script) in the
        // narrations table so voice_name/voice_id persist per narration. Ignored
        // if the table isn't present yet (run migration 0007_narrations.sql).
        try {
          final nReq = await http.postUrl(Uri.parse('$url/rest/v1/narrations'));
          sbh.forEach(nReq.headers.set);
          nReq.headers.set('Prefer', 'return=minimal');
          nReq.headers.set('resolution', 'merge-duplicates'); // harmless if unsupported
          nReq.headers.contentType = ContentType.json;
          nReq.add(utf8.encode(jsonEncode({
            'content_id': s.id,
            'content_type': 'species',
            'park_id': destId,
            'title': s.commonName,
            'narration_type': 'standard_ranger',
            'voice_name': voiceName,
            'voice_id': voiceId,
            'script': script,
            'audio_url': publicUrl,
            'duration': _composer.estimateSeconds(script),
            'status': 'published',
            'approved': true,
            'generated_at': DateTime.now().toUtc().toIso8601String(),
          })));
          final nRes = await nReq.close();
          await nRes.drain<void>();
        } catch (_) {/* narrations table not present yet */}

        generated++;
        stdout.writeln('  ✓ ${s.commonName} (${(bytes.length / 1024).round()} KB) -> $path');
      } catch (e) {
        failed++;
        stderr.writeln('  ✗ ${s.commonName}: $e');
      }
    }

    stdout.writeln('\n=== Done ===');
    stdout.writeln('generated: $generated  skipped(existing): $skipped  failed: $failed');
  } catch (e) {
    stderr.writeln('FAILED: $e');
    exitCode = 1;
  } finally {
    http.close(force: true);
  }
}
