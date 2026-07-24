import 'package:flutter/material.dart';

/// Central color palette for ExplorerOS.
///
/// This is the single source of truth for color in the app. Widgets must NEVER
/// hardcode `Color(0xFF...)` values inline — they pull from here (or, better,
/// from `Theme.of(context).colorScheme`, which is built from these tokens in
/// `app_theme.dart`). Centralizing color lets us re-skin the whole app — or add
/// per-destination theming later — from one file.
///
/// Palette inspiration: National Geographic / National Park Service — deep
/// forest greens, warm trail sand/gold, and calm neutral surfaces.
class AppColors {
  const AppColors._();

  // --- Brand ---------------------------------------------------------------
  static const Color primary = Color(0xFF1F6F54); // deep forest green
  static const Color primaryDark = Color(0xFF124331);
  static const Color primaryLight = Color(0xFF3E9B78);
  static const Color secondary = Color(0xFFE0A458); // warm trail gold/sand
  static const Color accent = Color(0xFF2C6E8F); // sky/water blue

  // --- Light neutrals ------------------------------------------------------
  static const Color background = Color(0xFFF5F6F3);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFEDEFEA); // subtle raised fills

  // --- Dark neutrals -------------------------------------------------------
  static const Color backgroundDark = Color(0xFF0F1311);
  static const Color surfaceDark = Color(0xFF1A1F1C);
  static const Color surfaceAltDark = Color(0xFF232A26);

  // --- Text ----------------------------------------------------------------
  static const Color textPrimary = Color(0xFF16211C);
  static const Color textSecondary = Color(0xFF5B6560);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textPrimaryDark = Color(0xFFF2F4F1);
  static const Color textSecondaryDark = Color(0xFFA9B2AD);

  // --- Feedback ------------------------------------------------------------
  static const Color error = Color(0xFFC0392B);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFE08A00);

  // --- Gradients (used by hero areas / feature cards) ----------------------
  /// Primary hero gradient — evokes a forest horizon at dusk.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, accent],
  );

  /// Warm accent gradient for highlight cards (e.g. Radio).
  static const LinearGradient sunsetGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE0A458), Color(0xFFC0653B)],
  );
}
