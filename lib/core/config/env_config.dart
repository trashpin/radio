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
  static const String _supabaseAnonKeyKey = 'SUPABASE_ANON_KEY';

  static String get supabaseUrl => dotenv.maybeGet(_supabaseUrlKey) ?? '';
  static String get supabaseAnonKey =>
      dotenv.maybeGet(_supabaseAnonKeyKey) ?? '';

  /// True only when both Supabase values are present.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
