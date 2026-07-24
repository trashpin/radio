import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';

/// Owns the connection to the Supabase backend.
///
/// The backend already exists (Supabase + Base44 Admin + GitHub). The mobile
/// app is a READ-ONLY client of destination content, so this service is the
/// single doorway through which the app talks to Supabase.
///
/// Configuration (URL + anon key) is read at runtime from a `.env` file via
/// `flutter_dotenv` — nothing is hardcoded and the file is gitignored. If the
/// values are absent (e.g. running the UI without a backend), initialization is
/// skipped gracefully so the app still boots and surfaces a friendly message.
class SupabaseService {
  const SupabaseService._();

  /// Reads a value from the loaded `.env`, returning '' when unset so callers
  /// can treat "missing" and "blank" the same way.
  static String _env(String key) => dotenv.maybeGet(key) ?? '';

  static String get _url => _env(AppConstants.supabaseUrlEnvKey);
  static String get _anonKey => _env(AppConstants.supabaseAnonKeyEnvKey);

  /// True only when both config values are present in `.env`.
  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;

  /// Initializes Supabase. Call this once from `main()` before `runApp`.
  static Future<void> initialize() async {
    if (!isConfigured) {
      debugPrint(
        'SupabaseService: SUPABASE_URL / SUPABASE_ANON_KEY missing from .env — '
        'running without a backend connection.',
      );
      return;
    }
    // The anon key is Supabase's publishable client key. Newer SDKs prefer the
    // `publishableKey` parameter (the old `anonKey` is deprecated).
    await Supabase.initialize(url: _url, publishableKey: _anonKey);
  }

  /// The shared Supabase client. Only valid after [initialize] has run with
  /// valid configuration.
  static SupabaseClient get client => Supabase.instance.client;
}

/// Riverpod provider exposing the Supabase client to the widget tree.
///
/// Repositories/feature providers depend on this instead of touching the global
/// singleton directly, which keeps the code testable (the provider can be
/// overridden with a mock in tests).
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseService.client;
});
