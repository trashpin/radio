import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:explorer_os_mobile/core/config/env_config.dart';

/// Owns the connection to the Supabase backend.
///
/// The backend already exists (Supabase + Base44 Admin + GitHub). The mobile
/// app is a READ-ONLY client of destination content, so this service is the
/// single doorway through which the app talks to Supabase. Config comes from
/// [EnvConfig] (a `.env` file) — nothing is hardcoded. If config is absent the
/// app still boots and features surface a friendly "not connected" state.
class SupabaseService {
  const SupabaseService._();

  /// True when Supabase credentials are available.
  static bool get isConfigured => EnvConfig.hasSupabase;

  /// Initializes Supabase. Call once from `main()` before `runApp`.
  static Future<void> initialize() async {
    if (!isConfigured) {
      debugPrint(
        'SupabaseService: SUPABASE_URL / SUPABASE_ANON_KEY missing from .env — '
        'running without a backend connection.',
      );
      return;
    }
    // The anon key is Supabase's publishable client key (old `anonKey` param is
    // deprecated in favor of `publishableKey`).
    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      publishableKey: EnvConfig.supabaseAnonKey,
    );
  }

  /// Shared client — only valid after [initialize] runs with valid config.
  static SupabaseClient get client => Supabase.instance.client;
}

/// Exposes the Supabase client to the widget tree so repositories can depend on
/// it (and tests can override it with a mock).
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseService.client;
});
