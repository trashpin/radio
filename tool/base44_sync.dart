// Base44 -> Supabase content sync.
//
// Pulls Base44 content entities (Plant, Wildlife, ...) for a park and upserts
// them into the Supabase `species` catalog, bringing image + narration + facts
// together on one record so the app can show the picture and speak/play the
// narration when a species is opened.
//
// Narration: Base44 stores a spoken `narration` script (and sometimes an
// `audio_url`). When an `audio_url` exists we also create a linked `media`
// audio row (media.species_id) so the app plays the real file; otherwise the
// narration text rides on the species row and the app reads it aloud via TTS.
//
// Run:
//   SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   BASE44_APP_ID=... BASE44_API_KEY=... \
//   dart run tool/base44_sync.dart --park ocala [--dry-run]
//
// Idempotent: re-running updates existing species (matched by park +
// normalized common name) instead of duplicating them.
import 'dart:convert';
import 'dart:io';

const _entityCategory = <String, String>{
  'Plant': 'plants',
  'GeologyFeature': 'geology',
};

// Base44 Wildlife.category -> app discovery category token.
const _wildlifeCategory = <String, String>{
  'mammal': 'animals',
  'bird': 'birds',
  'reptile': 'reptiles',
  'amphibian': 'amphibians',
  'fish': 'fish',
  'insect': 'insects',
  'pollinator': 'insects',
};

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '_')
    .replaceAll(RegExp(r'[^a-z0-9_]'), '')
    .replaceAll(RegExp(r'_+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

/// base44.app file URL -> public media CDN URL.
String? _resolveImage(String? url) {
  if (url == null || url.isEmpty) return null;
  const marker = '/files/mp/public/';
  final i = url.indexOf(marker);
  if (i >= 0) {
    return 'https://media.base44.com/images/public/${url.substring(i + marker.length)}';
  }
  return url;
}

String? _joinArray(dynamic v) {
  if (v is List && v.isNotEmpty) {
    return v.map((e) => e.toString()).join('\n• ');
  }
  if (v is String && v.isNotEmpty) return v;
  return null;
}

class _Http {
  final HttpClient _c = HttpClient();

  Future<dynamic> getJson(String url, Map<String, String> headers) async {
    final req = await _c.getUrl(Uri.parse(url));
    headers.forEach(req.headers.set);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) {
      throw 'GET $url -> ${res.statusCode}: ${body.substring(0, body.length.clamp(0, 300))}';
    }
    return body.isEmpty ? null : jsonDecode(body);
  }

  Future<String> send(String method, String url, Map<String, String> headers,
      Object? jsonBody) async {
    final req = await _c.openUrl(method, Uri.parse(url));
    headers.forEach(req.headers.set);
    if (jsonBody != null) {
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(jsonBody)));
    }
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) {
      throw '$method $url -> ${res.statusCode}: ${body.substring(0, body.length.clamp(0, 300))}';
    }
    return body;
  }

  void close() => _c.close(force: true);
}

String _arg(List<String> args, String name, String fallback) {
  final i = args.indexOf('--$name');
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : fallback;
}

Future<void> main(List<String> args) async {
  final parkCode = _arg(args, 'park', 'ocala');
  final dryRun = args.contains('--dry-run');
  final entities = _arg(args, 'entities', 'Plant,Wildlife').split(',');

  final sbUrl = Platform.environment['SUPABASE_URL'] ??
      'https://qqeyvhcgirmfokoftiuz.supabase.co';
  final sbKey = Platform.environment['SUPABASE_SERVICE_KEY'] ??
      Platform.environment['SUPABASE_ANON_KEY'] ??
      '';
  final appId = Platform.environment['BASE44_APP_ID'] ?? '';
  final apiKey = Platform.environment['BASE44_API_KEY'] ?? '';
  if (sbKey.isEmpty || appId.isEmpty || apiKey.isEmpty) {
    stderr.writeln('Missing env: need SUPABASE_SERVICE_KEY (or SUPABASE_ANON_KEY), '
        'BASE44_APP_ID, BASE44_API_KEY.');
    exit(2);
  }

  final http = _Http();
  final b44 = 'https://app.base44.com/api/apps/$appId/entities';
  final b44h = {'api_key': apiKey};
  final sbh = {'apikey': sbKey, 'Authorization': 'Bearer $sbKey'};

  Future<List<Map<String, dynamic>>> b44List(String entity,
      [String? parkId]) async {
    var url = '$b44/$entity?limit=1000';
    if (parkId != null) {
      url += '&q=${Uri.encodeComponent(jsonEncode({'park_id': parkId}))}';
    }
    final d = await http.getJson(url, b44h);
    final rows = d is List ? d : (d is Map ? (d['data'] ?? []) : []);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  try {
    // Resolve Base44 park + Supabase destination.
    final parks = await b44List('Park');
    final park = parks.firstWhere(
        (p) => (p['park_code'] ?? '').toString().toLowerCase() ==
            parkCode.toLowerCase(),
        orElse: () => throw 'Base44 park not found for code "$parkCode"');
    final parkId = park['id'].toString();
    final parkName = (park['name'] ?? '').toString();
    stdout.writeln('Base44 park: $parkName ($parkId)');

    final destOverride = _arg(args, 'destination-id', '');
    String destId;
    if (destOverride.isNotEmpty) {
      destId = destOverride;
    } else {
      final dests = await http.getJson(
          '$sbUrl/rest/v1/destinations?select=destination_id,name', sbh) as List;
      final match = dests.cast<Map<String, dynamic>>().firstWhere(
          (d) => _norm((d['name'] ?? '').toString()) == _norm(parkName),
          orElse: () =>
              throw 'No Supabase destination matches "$parkName". Pass --destination-id.');
      destId = match['destination_id'].toString();
    }
    stdout.writeln('Supabase destination_id: $destId');

    // Existing species for this destination (dedupe by normalized name).
    final existing = (await http.getJson(
            '$sbUrl/rest/v1/species?select=species_id,common_name&destination_id=eq.$destId',
            sbh) as List)
        .cast<Map<String, dynamic>>();
    final byName = <String, String>{
      for (final s in existing)
        _norm((s['common_name'] ?? '').toString()): s['species_id'].toString(),
    };

    var created = 0, updated = 0, withImage = 0, withNarration = 0, audioLinked = 0;

    for (final entity in entities) {
      final rows = await b44List(entity, parkId);
      stdout.writeln('\n$entity: ${rows.length} Base44 records');
      var order = 0;
      for (final r in rows) {
        // Prefer the curated common_name; skip Base44's scientific-name-only
        // duplicate records (category 'other', no common_name).
        final common = (r['common_name'] ?? '').toString().trim();
        final rawName = (r['name'] ?? '').toString().trim();
        final name = common.isNotEmpty ? common : rawName;
        if (name.isEmpty) continue;

        final String? category;
        if (entity == 'Wildlife') {
          category = _wildlifeCategory[(r['category'] ?? '').toString()];
          if (category == null || common.isEmpty) continue; // skip junk dupes
        } else {
          category = _entityCategory[entity] ?? 'plants';
        }
        final key = _norm(name);

        final image = _resolveImage(r['photo_url'] as String?);
        final narration =
            (r['narration'] ?? r['script'] ?? '').toString().trim();
        final description =
            (r['description'] ?? '').toString().trim().isNotEmpty
                ? (r['description'] as String).trim()
                : (narration.isNotEmpty ? narration : null);

        final payload = <String, dynamic>{
          'category': category,
          'common_name': name,
          'scientific_name': r['scientific_name'],
          'description': description,
          'diet': r['diet'],
          'behavior': r['behavior'],
          'conservation_status': _mapConservation(r['conservation_status']),
          'safety_info': r['safety_tips'] ?? r['safety_info'],
          'fun_facts':
              _joinArray(r['fun_facts'] ?? r['interesting_facts']) ??
                  (narration.isNotEmpty ? narration : null),
          'destination_id': destId,
          'published': true,
          'sort_order': order++,
        };
        if (image != null) payload['hero_image'] = image;
        payload.removeWhere((k, v) => v == null);

        if (image != null) withImage++;
        if (narration.isNotEmpty || (description?.isNotEmpty ?? false)) {
          withNarration++;
        }

        if (dryRun) {
          stdout.writeln('  [dry] ${byName.containsKey(key) ? 'update' : 'create'}'
              ' $name ($category)${image != null ? ' +img' : ''}');
          continue;
        }

        String speciesId;
        if (byName.containsKey(key)) {
          speciesId = byName[key]!;
          await http.send('PATCH',
              '$sbUrl/rest/v1/species?species_id=eq.$speciesId',
              {...sbh, 'Prefer': 'return=minimal'}, payload);
          updated++;
        } else {
          final body = await http.send('POST', '$sbUrl/rest/v1/species',
              {...sbh, 'Prefer': 'return=representation'}, payload);
          speciesId = (jsonDecode(body) as List).first['species_id'].toString();
          byName[key] = speciesId;
          created++;
        }

        // Link narration audio file if Base44 has one.
        final audio = r['audio_url'] as String?;
        if (!dryRun && audio != null && audio.isNotEmpty) {
          // Avoid duplicates: only insert if no audio media exists yet.
          final existingAudio = await http.getJson(
              '$sbUrl/rest/v1/media?select=media_id&species_id=eq.$speciesId&media_type=eq.audio',
              sbh) as List;
          if (existingAudio.isEmpty) {
            await http.send('POST', '$sbUrl/rest/v1/media',
                {...sbh, 'Prefer': 'return=minimal'}, {
              'species_id': speciesId,
              'destination_id': destId,
              'media_type': 'audio',
              'title': '$name narration',
              'file_url': audio,
              'published': true,
            });
            audioLinked++;
          }
        }
      }
    }

    stdout.writeln('\n=== Sync complete ===');
    stdout.writeln('created: $created  updated: $updated');
    stdout.writeln('with image: $withImage  with narration text: $withNarration'
        '  audio files linked: $audioLinked');
  } catch (e) {
    stderr.writeln('SYNC FAILED: $e');
    exitCode = 1;
  } finally {
    http.close();
  }
}

// Map free-form Base44 conservation labels to the species enum-ish text.
String? _mapConservation(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty) return null;
  return s;
}
