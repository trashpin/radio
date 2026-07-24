import 'package:flutter/material.dart';

/// Central color palette for ExplorerOS-Mobile.
///
/// Defining every color in one place means we can re-theme the entire app
/// (or introduce per-destination theming later) by editing a single file.
/// Widgets should NEVER use raw `Color(0xFF...)` values inline — they should
/// pull from here (or, better, from `Theme.of(context)`).
class AppColors {
  const AppColors._();

  // Brand palette — inspired by outdoor exploration (deep forest + trail).
  static const Color primary = Color(0xFF2E7D5B); // forest green
  static const Color primaryDark = Color(0xFF1B5E3F);
  static const Color secondary = Color(0xFFE0A458); // trail/sand accent

  // Neutral surfaces used by light theme.
  static const Color background = Color(0xFFF6F7F5);
  static const Color surface = Color(0xFFFFFFFF);

  // Neutral surfaces used by dark theme.
  static const Color backgroundDark = Color(0xFF121513);
  static const Color surfaceDark = Color(0xFF1D211E);

  // Text colors.
  static const Color textPrimary = Color(0xFF1A1C1B);
  static const Color textSecondary = Color(0xFF5B615E);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Feedback / status colors.
  static const Color error = Color(0xFFC0392B);
  static const Color success = Color(0xFF2E7D32);
}
