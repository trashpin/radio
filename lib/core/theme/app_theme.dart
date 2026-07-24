import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Assembles the light and dark [ThemeData] for ExplorerOS-Mobile.
///
/// This is the single source of truth for how the app looks. `MaterialApp`
/// (in `app.dart`) consumes `AppTheme.light` and `AppTheme.dark`, so changing
/// a color or component style here updates the whole app at once.
class AppTheme {
  const AppTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      error: AppColors.error,
      brightness: Brightness.light,
    );
    return _base(scheme, AppColors.background, AppColors.textPrimary);
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surfaceDark,
      error: AppColors.error,
      brightness: Brightness.dark,
    );
    return _base(scheme, AppColors.backgroundDark, AppColors.textOnPrimary);
  }

  /// Shared theme configuration used by both light and dark variants to avoid
  /// duplication.
  static ThemeData _base(
    ColorScheme scheme,
    Color scaffoldBackground,
    Color primaryTextColor,
  ) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: AppTypography.textTheme(primaryTextColor),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scheme.surface,
        foregroundColor: primaryTextColor,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}
