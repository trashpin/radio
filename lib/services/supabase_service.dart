import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';

/// Owns the connection to the Supabase backend.
///
/// The backend already exists (Supabase + Base44 Admin + GitHub). The mobile
/// app is a READ-ONLY client of destination content, so this service is the
/// single doorway through which the app talks to Supabase.
///
/// Configuration (URL + anon key) is injected at build/run time via
/// `--dart-define` and read here — nothing is hardcoded. If the values are
/// absent (e.g. running the UI locally without a backend), initialization is
/// skipped gracefully so the app foundation still boots.
class SupabaseService {
  const SupabaseService._();

  /// Read from `--dart-define=SUPABASE_URL=...`.
  static const String _url =
      String.fromEnvironment(AppConstants.supabaseUrlEnvKey);

  /// Read from `--dart-define=SUPABASE_ANON_KEY=...`.
  static const String _anonKey =
      String.fromEnvironment(AppConstants.supabaseAnonKeyEnvKey);

  /// True only when both config values were provided at build time.
  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;

  /// Initializes Supabase. Call this once from `main()` before `runApp`.
  static Future<void> initialize() async {
    if (!isConfigured) {
      debugPrint(
        'SupabaseService: SUPABASE_URL / SUPABASE_ANON_KEY not set — '
        'running without a backend connection. Provide them via --dart-define.',
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
