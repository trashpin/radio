// Creates (or updates) the ExplorerOS developer test account and grants admin.
//
//   Email:    developer@exploreros.app
//   Password: ExplorerOS123!
//
// Uses the Supabase Auth Admin API (requires the SERVICE ROLE key) to create a
// pre-confirmed user, then sets profiles.role = 'admin'.
//
// Usage:
//   SUPABASE_URL=... SUPABASE_SERVICE_KEY=<service_role key> \
//   dart run tool/create_test_account.dart
import 'dart:convert';
import 'dart:io';

const _email = 'developer@exploreros.app';
const _password = 'ExplorerOS123!';

Future<void> main(List<String> args) async {
  final url = (Platform.environment['SUPABASE_URL'] ??
          'https://qqeyvhcgirmfokoftiuz.supabase.co')
      .replaceAll(RegExp(r'/$'), '');
  final key = Platform.environment['SUPABASE_SERVICE_KEY'] ?? '';
  if (key.isEmpty) {
    stderr.writeln('Missing SUPABASE_SERVICE_KEY (service role key required).');
    exit(2);
  }
  final http = HttpClient();
  final headers = {'apikey': key, 'Authorization': 'Bearer $key'};

  // 1) Create the pre-confirmed user via the Admin API.
  String? userId;
  final createReq =
      await http.postUrl(Uri.parse('$url/auth/v1/admin/users'));
  headers.forEach(createReq.headers.set);
  createReq.headers.contentType = ContentType.json;
  createReq.add(utf8.encode(jsonEncode({
    'email': _email,
    'password': _password,
    'email_confirm': true,
    'user_metadata': {
      'first_name': 'Developer',
      'last_name': 'Account',
      'full_name': 'Developer Account',
      'role': 'admin',
    },
    'app_metadata': {'role': 'admin'},
  })));
  final createRes = await createReq.close();
  final createBody = await createRes.transform(utf8.decoder).join();
  if (createRes.statusCode < 300) {
    userId = (jsonDecode(createBody)['id'] ?? jsonDecode(createBody)['user']?['id'])
        ?.toString();
    stdout.writeln('✓ Created user $_email (id: $userId)');
  } else if (createRes.statusCode == 422 ||
      createBody.contains('already been registered') ||
      createBody.contains('already exists')) {
    stdout.writeln('• User already exists — looking it up…');
    // Find the existing user id.
    final listReq = await http.getUrl(Uri.parse(
        '$url/auth/v1/admin/users?per_page=200'));
    headers.forEach(listReq.headers.set);
    final listRes = await listReq.close();
    final listBody = await listRes.transform(utf8.decoder).join();
    if (listRes.statusCode < 300) {
      final users = (jsonDecode(listBody)['users'] as List?) ?? const [];
      for (final u in users) {
        if ((u['email'] ?? '').toString().toLowerCase() == _email) {
          userId = u['id'].toString();
          break;
        }
      }
      stdout.writeln('  found id: $userId');
    }
  } else {
    stderr.writeln('✗ Admin create failed ${createRes.statusCode}: $createBody');
    stderr.writeln('\n>> The Auth Admin API requires the SERVICE ROLE key. If '
        'SUPABASE_SERVICE_KEY is an anon key, create the user in the Supabase '
        'dashboard (Authentication → Users → Add user, confirm email), then '
        're-run to set the admin role.');
    http.close(force: true);
    exit(1);
  }

  // 2) Grant admin in profiles.
  if (userId != null) {
    final patchReq = await http.openUrl(
        'PATCH', Uri.parse('$url/rest/v1/profiles?id=eq.$userId'));
    headers.forEach(patchReq.headers.set);
    patchReq.headers.set('Prefer', 'return=minimal');
    patchReq.headers.contentType = ContentType.json;
    patchReq.add(utf8.encode(jsonEncode({
      'role': 'admin',
      'email': _email,
      'first_name': 'Developer',
      'last_name': 'Account',
      'display_name': 'Developer Account',
    })));
    final patchRes = await patchReq.close();
    final patchBody = await patchRes.transform(utf8.decoder).join();
    if (patchRes.statusCode < 300) {
      stdout.writeln('✓ Granted admin role in profiles.');
    } else {
      stderr.writeln('! profiles update ${patchRes.statusCode}: $patchBody '
          '(the on-signup trigger may not have created the row yet).');
    }
  }

  stdout.writeln('\nDeveloper account ready:\n  $_email / $_password');
  http.close(force: true);
}
