/// App-wide, non-visual constants for ExplorerOS.
///
/// Brand-level values and backend identifiers that are reused across features
/// live here. Visual tokens (spacing, radius, colors, durations) belong in the
/// design system under `core/theme/`, and environment/config keys live in
/// `core/config/` — not here.
///
/// IMPORTANT: The app is READ-ONLY for destination content and must NOT
/// hardcode any destination data (National Park Buddy, Route 66, etc.). Only
/// neutral, brand-level constants belong here.
class AppConstants {
  const AppConstants._();

  /// Human-readable product name.
  static const String appName = 'ExplorerOS';

  /// Tagline shown in hero/welcome areas.
  static const String appTagline = 'Your guide to the great outdoors';

  /// Prompt shown under the hero greeting on the dashboard.
  static const String appHeroPrompt = 'Ready for your next adventure?';

  /// Placeholder explorer name used in the personalized greeting until real
  /// user/session data is wired up (no fake account is implied).
  static const String placeholderExplorerName = 'Explorer';

  /// Name of the read-only destinations table in Supabase.
  static const String destinationsTable = 'destinations';
}
