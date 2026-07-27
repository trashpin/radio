// Destination research tool: OpenAI -> knowledge_base, driven by the job queue.
//
// Processes pending `generation_jobs` (or a single --destination) by asking the
// LLM for structured, categorized facts about the destination and inserting
// them into knowledge_base as review drafts. Updates each job's status.
//
// Run:
//   OPENAI_API_KEY=... SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
//   dart run tool/research_destination.dart [--destination "Ocala National Forest" --category national_forest --state Florida] [--limit 5] [--dry-run]
import 'dart:convert';
import 'dart:io';

const _model = 'gpt-4o-mini';

String _arg(List<String> a, String n, String d) {
  final i = a.indexOf('--$n');
  return (i >= 0 && i + 1 < a.length) ? a[i + 1] : d;
}

Future<void> main(List<String> args) async {
  final oneDest = _arg(args, 'destination', '');
  final oneCat = _arg(args, 'category', 'national_park');
  final oneState = _arg(args, 'state', '');
  final limit = int.tryParse(_arg(args, 'limit', '5')) ?? 5;
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

  Future<void> patchJob(String id, Map<String, dynamic> v) async {
    final r =
        await http.openUrl('PATCH', Uri.parse('$url/rest/v1/generation_jobs?id=eq.$id'));
    sbh.forEach(r.headers.set);
    r.headers.set('Prefer', 'return=minimal');
    r.headers.contentType = ContentType.json;
    r.add(utf8.encode(jsonEncode(v)));
    await (await r.close()).drain<void>();
  }

  Future<int> research({
    required String destination,
    required String category,
    String? state,
  }) async {
    final sys = 'You are a meticulous park researcher. You only state verifiable, '
        'widely-documented facts and never invent specifics.';
    final user = 'Provide structured facts about "$destination"'
        '${state != null && state.isNotEmpty ? ', $state' : ''} '
        '(type: $category). Return ONLY JSON {"facts":[{"category":"History",'
        '"title":"...","description":"1-3 sentences","source":"general knowledge",'
        '"confidence":0.0-1.0}]} with 15-25 facts spanning: History, Geography, '
        'Geology, Wildlife, Birds, Plants, Trees, Springs, Rivers, Lakes, Trails, '
        'Campgrounds, Recreation, Conservation, Interesting Facts, '
        'Native American History, Historic Events, Famous People, Local Legends.';

    final req =
        await http.postUrl(Uri.parse('https://api.openai.com/v1/chat/completions'));
    req.headers.set('Authorization', 'Bearer $openai');
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode({
      'model': _model,
      'temperature': 0.5,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': sys},
        {'role': 'user', 'content': user},
      ],
    })));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 300) {
      throw 'OpenAI ${res.statusCode}: ${body.substring(0, body.length.clamp(0, 300))}';
    }
    final content = jsonDecode(body)['choices'][0]['message']['content'] as String;
    final facts = (jsonDecode(content)['facts'] as List?) ?? const [];
    var saved = 0;
    for (final f in facts) {
      try {
        final ins = await http.postUrl(Uri.parse('$url/rest/v1/knowledge_base'));
        sbh.forEach(ins.headers.set);
        ins.headers.set('Prefer', 'return=minimal');
        ins.headers.contentType = ContentType.json;
        ins.add(utf8.encode(jsonEncode({
          'destination': destination,
          'destination_category': category,
          'category': (f['category'] ?? 'General').toString(),
          'title': (f['title'] ?? '').toString(),
          'description': (f['description'] ?? '').toString(),
          'source': (f['source'] ?? 'general knowledge').toString(),
          'confidence_score': (f['confidence'] is num) ? f['confidence'] : 0.7,
        })));
        final insRes = await ins.close();
        await insRes.drain<void>();
        if (insRes.statusCode < 300) saved++;
      } catch (_) {}
    }
    return saved;
  }

  try {
    // Build the work list: either one explicit destination, or pending jobs.
    final jobs = <Map<String, dynamic>>[];
    if (oneDest.isNotEmpty) {
      jobs.add({'destination': oneDest, 'destination_category': oneCat, 'state': oneState});
    } else {
      final getReq = await http.getUrl(Uri.parse('$url/rest/v1/generation_jobs'
          '?select=*&status=eq.pending&order=created_at'));
      sbh.forEach(getReq.headers.set);
      final getRes = await getReq.close();
      final body = await getRes.transform(utf8.decoder).join();
      if (getRes.statusCode >= 300) throw 'load jobs ${getRes.statusCode}: $body';
      jobs.addAll((jsonDecode(body) as List).cast<Map<String, dynamic>>());
    }
    final work = jobs.length > limit ? jobs.sublist(0, limit) : jobs;
    stdout.writeln('research targets: ${work.length}');

    for (final j in work) {
      final id = j['id']?.toString();
      final dest = (j['destination'] ?? '').toString();
      final cat = (j['destination_category'] ?? oneCat).toString();
      final state = (j['state'] ?? oneState) as String?;
      if (dryRun) {
        stdout.writeln('  [dry] research "$dest" ($cat)');
        continue;
      }
      if (id != null) await patchJob(id, {'status': 'researching', 'progress': 20});
      try {
        final saved = await research(destination: dest, category: cat, state: state);
        stdout.writeln('  ✓ $dest: $saved facts');
        if (id != null) {
          await patchJob(id, {
            'status': 'waiting_for_review',
            'progress': 100,
            'message': '$saved facts researched',
          });
        }
      } catch (e) {
        stderr.writeln('  ✗ $dest: $e');
        if (id != null) {
          await patchJob(id, {'status': 'failed', 'message': '$e'});
        }
      }
    }
    stdout.writeln('\n=== Done ===');
  } catch (e) {
    stderr.writeln('FAILED: $e');
    exitCode = 1;
  } finally {
    http.close(force: true);
  }
}
