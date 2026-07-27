// AI Narration generator: OpenAI (grounded ONLY in ExplorerOS knowledge) ->
// destination_narrations. Writes ranger-style scripts with quality-control
// metrics (word count, speaking time @150 wpm, duplicate score) as review
// drafts. Never invents facts — emits a needs_review placeholder when a
// destination has no knowledge.
//
// Run:
//   OPENAI_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/generate_narration.dart --destination "Ocala National Forest" \
//     [--types arrival,fun_facts,wildlife] [--mode all|missing] \
//     [--max-variations 1] [--dry-run]
//
// With no --destination it processes pending generation_jobs (job_type
// 'narration'), using each job's destination + notes (mode=...).
import 'dart:convert';
import 'dart:io';

import 'package:explorer_os_mobile/features/narration/narration_qc.dart';

const _model = 'gpt-4o-mini';

// (dbValue, human label, target words, variation count) for the 25 script types.
const _types = <List<Object>>[
  ['arrival', 'Arrival welcome', 110, 3],
  ['quick_intro', 'Quick introduction', 90, 1],
  ['main_history', 'Main history', 150, 5],
  ['extended_history', 'Extended history', 220, 1],
  ['things_to_notice', 'Things to notice around you', 130, 1],
  ['architecture', 'Architecture', 130, 1],
  ['wildlife', 'Wildlife you might see', 130, 3],
  ['plants', 'Plants and flora', 130, 1],
  ['trees', 'Trees', 120, 1],
  ['birds', 'Birds', 120, 1],
  ['geology', 'Geology and landscape', 140, 1],
  ['photography_tips', 'Photography tips', 110, 1],
  ['fun_facts', 'Fun facts', 120, 5],
  ['family_version', 'Family-friendly overview', 120, 3],
  ['kids_version', 'Version for kids', 100, 3],
  ['accessibility', 'Accessibility information', 120, 1],
  ['scenic_highlights', 'Scenic highlights', 130, 1],
  ['hidden_gems', 'Hidden gems', 120, 1],
  ['nearby_attractions', 'Nearby attractions', 120, 1],
  ['departure', 'Departure send-off', 100, 3],
  ['night_tour', 'Night tour', 130, 1],
  ['sunrise_tour', 'Sunrise tour', 120, 1],
  ['sunset_tour', 'Sunset tour', 120, 1],
  ['rainy_day', 'Rainy day version', 120, 1],
  ['emergency_info', 'Emergency information', 110, 1],
];

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

Future<void> main(List<String> args) async {
  final destination = _arg(args, 'destination', '');
  final typesArg = _arg(args, 'types', 'all');
  final mode = _arg(args, 'mode', 'all'); // all | missing
  final maxVar = int.tryParse(_arg(args, 'max-variations', '1')) ?? 1;
  final dryRun = args.contains('--dry-run');

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

  // Resolve which destinations to process.
  final targets = <String>[];
  if (destination.isNotEmpty) {
    targets.add(destination);
  } else {
    final jobs = await get('generation_jobs?job_type=eq.narration&status=eq.pending'
        '&select=destination&limit=20');
    for (final j in jobs) {
      final d = (j['destination'] ?? '').toString();
      if (d.isNotEmpty) targets.add(d);
    }
    if (targets.isEmpty) {
      stdout.writeln('No --destination and no pending narration jobs.');
      http.close();
      return;
    }
  }

  final wantTypes = typesArg == 'all'
      ? _types.map((t) => t[0] as String).toList()
      : typesArg.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  for (final destName in targets) {
    await _run(
      http: http,
      get: get,
      url: url,
      sbh: sbh,
      openai: openai,
      destName: destName,
      wantTypes: wantTypes,
      mode: mode,
      maxVar: maxVar,
      dryRun: dryRun,
    );
  }
  http.close(force: true);
}

Future<void> _run({
  required HttpClient http,
  required Future<List<Map<String, dynamic>>> Function(String) get,
  required String url,
  required Map<String, String> sbh,
  required String openai,
  required String destName,
  required List<String> wantTypes,
  required String mode,
  required int maxVar,
  required bool dryRun,
}) async {
  final destRows = await get('destinations?name=eq.${Uri.encodeComponent(destName)}'
      '&select=destination_id,description,destination_type,county,state_province&limit=1');
  if (destRows.isEmpty) {
    stderr.writeln('! destination not found: "$destName"');
    return;
  }
  final dest = destRows.first;
  final destId = dest['destination_id']?.toString();
  final description = (dest['description'] ?? '').toString();

  // Gather ExplorerOS knowledge (no external facts).
  final facts = await get('knowledge_base?destination=eq.${Uri.encodeComponent(destName)}'
      '&select=category,title,description&limit=80');
  final species = destId == null
      ? <Map<String, dynamic>>[]
      : await get('species?destination_id=eq.$destId'
          '&select=common_name,category,description&limit=60');

  final knowledge = StringBuffer();
  if (description.isNotEmpty) knowledge.writeln('Description: $description');
  for (final f in facts) {
    knowledge.writeln('- [${f['category']}] ${f['title']}: ${f['description'] ?? ''}');
  }
  for (final s in species) {
    knowledge.writeln('- [species/${s['category']}] ${s['common_name']}: '
        '${s['description'] ?? ''}');
  }
  final knowledgeText = knowledge.toString().trim();
  final hasKnowledge = knowledgeText.length > 40;

  // Skip already-present types when mode=missing.
  Set<String> existing = {};
  if (mode == 'missing' && destId != null) {
    final have = await get('destination_narrations?destination_id=eq.$destId'
        '&select=script_type');
    existing = have.map((r) => (r['script_type'] ?? '').toString()).toSet();
  }

  stdout.writeln('\n== $destName (${hasKnowledge ? '${facts.length} facts, '
      '${species.length} species' : 'NO knowledge — placeholders'}) ==');

  var ok = 0, placeholders = 0, fail = 0;
  for (final entry in _types) {
    final type = entry[0] as String;
    if (!wantTypes.contains(type)) continue;
    if (existing.contains(type)) continue;
    final label = entry[1] as String;
    final targetWords = entry[2] as int;
    final count = (entry[3] as int).clamp(1, maxVar);

    // No knowledge → write a single needs_review placeholder, no LLM call.
    if (!hasKnowledge) {
      placeholders++;
      if (!dryRun && destId != null) {
        await _insert(http, url, sbh, {
          'destination_id': destId,
          'script_type': type,
          'title': '[Needs info] $label — $destName',
          'script': 'Placeholder: no verified ExplorerOS knowledge exists for '
              '"$destName" yet. An administrator should add facts (history, '
              'wildlife, description) before generating $label narration.',
          'status': 'needs_review',
          'needs_review': true,
          'fact_confidence': 0.0,
          'word_count': 0,
          'speaking_seconds': 0,
          'ai_model': _model,
        });
      }
      stdout.writeln('  … $type: needs_review placeholder');
      continue;
    }

    try {
      final versions = dryRun
          ? List.generate(count, (i) => {'title': '$label #$i', 'script': '(dry run)'})
          : await _generate(http, openai, destName, label, targetWords, count,
              knowledgeText);
      final scripts = versions.map((v) => (v['script'] ?? '').toString()).toList();
      for (var i = 0; i < versions.length; i++) {
        final v = versions[i];
        final script = (v['script'] ?? '').toString();
        final words = wordCount(script);
        final others = [...scripts]..removeAt(i);
        if (dryRun) {
          stdout.writeln('  [dry] $type v${i + 1}: ${v['title']}');
          continue;
        }
        await _insert(http, url, sbh, {
          'destination_id': destId,
          'script_type': type,
          'title': (v['title'] ?? '$label — $destName').toString(),
          'script': script,
          'variant': i + 1,
          'status': 'review',
          'word_count': words,
          'speaking_seconds': speakingSeconds(words),
          'readability_score': readabilityScore(script),
          'fact_confidence': 0.8,
          'duplicate_score': maxDuplicateScore(script, others),
          'ai_model': _model,
        });
        ok++;
      }
      if (!dryRun) stdout.writeln('  ✓ $type: ${versions.length} version(s)');
    } catch (e) {
      fail++;
      stderr.writeln('  ✗ $type: $e');
    }
  }
  stdout.writeln('  -> saved $ok, placeholders $placeholders, failed $fail');
}

Future<List<Map<String, dynamic>>> _generate(HttpClient http, String openai,
    String dest, String label, int targetWords, int count, String knowledge) async {
  final sys =
      'You are an experienced U.S. National Park ranger recording short spoken '
      'audio narration for visitors. Warm, friendly, natural, professional — '
      'never robotic. Tell a story; transition naturally; end with a touch of '
      'curiosity. Never read lists aloud. Never mention being an AI. Use ONLY '
      'the facts provided about this destination; do NOT invent specifics. If '
      'the facts are thin, keep it evocative but general rather than fabricating.';
  final user = 'Destination: "$dest".\n'
      'Write $count DISTINCT "$label" narration script(s), each about $targetWords '
      'words (~${(targetWords / 150 * 60).round()}s at 150 wpm), each taking a '
      'slightly different angle so they can rotate without sounding repetitive.\n\n'
      'ExplorerOS knowledge (the ONLY facts you may use):\n$knowledge\n\n'
      'Return ONLY strict JSON: {"versions":[{"title":"...","script":"..."}]}.';

  final req = await http.postUrl(Uri.parse('https://api.openai.com/v1/chat/completions'));
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
    throw 'OpenAI ${res.statusCode}: ${body.substring(0, body.length.clamp(0, 200))}';
  }
  final content = jsonDecode(body)['choices'][0]['message']['content'] as String;
  final versions = (jsonDecode(content)['versions'] as List?) ?? const [];
  if (versions.isEmpty) throw 'no versions returned';
  return versions.cast<Map<String, dynamic>>();
}

Future<void> _insert(HttpClient http, String url, Map<String, String> sbh,
    Map<String, dynamic> payload) async {
  final ins = await http.postUrl(Uri.parse('$url/rest/v1/destination_narrations'));
  sbh.forEach(ins.headers.set);
  ins.headers.set('Prefer', 'return=minimal');
  ins.headers.contentType = ContentType.json;
  ins.add(utf8.encode(jsonEncode(payload)));
  final res = await ins.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode >= 300) throw 'insert ${res.statusCode}: $body';
}
