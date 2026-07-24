/// App-wide constants for ExplorerOS-Mobile.
///
/// This file centralizes values that are reused across the app so that we never
/// scatter "magic strings" or "magic numbers" through the codebase.
///
/// IMPORTANT ARCHITECTURE RULE:
/// The mobile app is READ-ONLY for destination content and must NOT hardcode any
/// destination information (National Park Buddy, Florida Buddy, Route 66, etc.).
/// All destination data is fetched at runtime from the backend (Supabase).
/// The only things allowed here are neutral, brand-level app constants and the
/// *names of environment variables* used to locate the backend at runtime.
library;

class AppConstants {
  // This class is never instantiated; it is a namespace for static constants.
  const AppConstants._();

  /// Human-readable product name shown in the UI / app metadata.
  static const String appName = 'ExplorerOS';

  /// Default duration used for small UI animations (page fades, etc.).
  static const Duration defaultAnimationDuration = Duration(milliseconds: 250);

  /// Standard spacing scale (in logical pixels) used across widgets so that
  /// padding/margins stay visually consistent.
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;

  /// Shared corner radius for cards, buttons, and containers.
  static const double borderRadius = 12;

  // --- Backend configuration keys (NOT the secrets themselves) -------------
  // The real Supabase URL / anon key live in a gitignored `.env` file that is
  // loaded at runtime by `flutter_dotenv` (see `SupabaseService`). We only store
  // the *names* of those keys here; the values are never hardcoded.
  // Example `.env`:
  //   SUPABASE_URL=https://xxxx.supabase.co
  //   SUPABASE_ANON_KEY=eyJhbGciOi...
  static const String supabaseUrlEnvKey = 'SUPABASE_URL';
  static const String supabaseAnonKeyEnvKey = 'SUPABASE_ANON_KEY';

  /// Name of the destinations table in Supabase (read-only source of content).
  static const String destinationsTable = 'destinations';

  /// Filename of the runtime environment file loaded by `flutter_dotenv`.
  static const String envFileName = '.env';
}
