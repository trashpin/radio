import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to runtime environment configuration.
///
/// All environment values (loaded from the gitignored `.env` by
/// `flutter_dotenv`) are read through this one class, so the rest of the app
/// never touches raw string keys or `dotenv` directly. Keys/secrets are never
/// hardcoded — only their *names* live here.
class EnvConfig {
  const EnvConfig._();

  /// Name of the env file loaded at startup.
  static const String fileName = '.env';

  static const String _supabaseUrlKey = 'SUPABASE_URL';
  static const String _publishableKeyKey = 'SUPABASE_PUBLISHABLE_KEY';
  static const String _anonKeyKey = 'SUPABASE_ANON_KEY';

  static String get supabaseUrl => dotenv.maybeGet(_supabaseUrlKey) ?? '';

  /// Client key for the Supabase SDK. Prefers the explicit
  /// `SUPABASE_PUBLISHABLE_KEY`; falls back to `SUPABASE_ANON_KEY` for backward
  /// compatibility. Browser clients (web admin) MUST use a publishable/anon key.
  static String get supabaseAnonKey =>
      dotenv.maybeGet(_publishableKeyKey) ??
      dotenv.maybeGet(_anonKeyKey) ??
      '';

  /// True only when both Supabase values are present.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// True when the configured client key is a Supabase **secret** key
  /// (`sb_secret_…` or a `service_role` JWT). Such keys must NEVER be used in a
  /// browser — Supabase rejects them with HTTP 401. Used to surface a warning.
  static bool get usingSecretKey {
    final key = supabaseAnonKey;
    return key.startsWith('sb_secret_') || key.contains('service_role');
  }
}
