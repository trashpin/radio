import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explorer_os_mobile/core/config/env_config.dart';
import 'package:explorer_os_mobile/core/services/supabase_service.dart';

enum CheckKind { table, bucket }

/// Result of probing one table or bucket.
class ConnectionCheck {
  const ConnectionCheck(this.name, this.kind, this.ok, this.detail);
  final String name;
  final CheckKind kind;
  final bool ok;
  final String detail;
}

/// A snapshot of the admin's live Supabase connection health.
class AdminConnectionReport {
  const AdminConnectionReport({
    required this.configured,
    required this.url,
    this.keyWarning,
    this.checks = const [],
  });

  /// Whether SUPABASE_URL + a client key are present (app is wired to a backend).
  final bool configured;
  final String url;

  /// Non-null when the configured key is unsafe for browsers (secret key).
  final String? keyWarning;

  final List<ConnectionCheck> checks;

  bool get allOk => configured && checks.every((c) => c.ok);
  Iterable<ConnectionCheck> get failing => checks.where((c) => !c.ok);
}

/// Probes the tables and buckets the admin depends on, reporting per-item
/// status so the dashboard can surface missing tables/buckets/RLS/auth/storage
/// errors instead of failing silently.
class SupabaseDiagnosticsService {
  const SupabaseDiagnosticsService(this._client);
  final SupabaseClient _client;

  static const tables = [
    'destinations',
    'stops',
    'stories',
    'media',
    'knowledge_articles',
  ];
  static const buckets = ['mp3'];

  String _msg(Object e) {
    final text = e is PostgrestException
        ? e.message
        : e is StorageException
            ? e.message
            : e.toString();
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  Future<List<ConnectionCheck>> run() async {
    final results = <ConnectionCheck>[];
    for (final t in tables) {
      try {
        await _client.from(t).select('*').limit(1);
        results.add(ConnectionCheck(t, CheckKind.table, true, 'reachable'));
      } catch (e) {
        results.add(ConnectionCheck(t, CheckKind.table, false, _msg(e)));
      }
    }
    try {
      final list = await _client.storage.listBuckets();
      final names = list.map((b) => b.name).toSet();
      for (final b in buckets) {
        final present = names.contains(b);
        results.add(ConnectionCheck(
            b, CheckKind.bucket, present, present ? 'present' : 'missing'));
      }
    } catch (e) {
      for (final b in buckets) {
        results.add(ConnectionCheck(b, CheckKind.bucket, false, _msg(e)));
      }
    }
    return results;
  }
}

/// Live connection health for the admin. Degrades to a `configured: false`
/// report (no throw) when Supabase isn't configured, so the UI can prompt for
/// the missing SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY.
final adminConnectionProvider = FutureProvider<AdminConnectionReport>((ref) async {
  if (!SupabaseService.isConfigured) {
    return const AdminConnectionReport(configured: false, url: '');
  }
  final checks =
      await SupabaseDiagnosticsService(ref.watch(supabaseClientProvider)).run();
  return AdminConnectionReport(
    configured: true,
    url: EnvConfig.supabaseUrl,
    keyWarning: EnvConfig.usingSecretKey
        ? 'A secret key is configured — browsers are blocked by Supabase. '
            'Set SUPABASE_PUBLISHABLE_KEY to the sb_publishable_ (anon) key.'
        : null,
    checks: checks,
  );
});
