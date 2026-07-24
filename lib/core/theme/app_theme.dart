import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';
import 'package:explorer_os_mobile/core/theme/app_radius.dart';
import 'package:explorer_os_mobile/core/theme/app_spacing.dart';
import 'package:explorer_os_mobile/core/theme/app_typography.dart';

/// Assembles the light & dark [ThemeData] for ExplorerOS from the design-system
/// tokens (colors, typography, spacing, radius).
///
/// This is the ONLY place component-level styling defaults live: card shape,
/// button size/shape, navigation bar, app bar, inputs. Because these are set on
/// the theme, individual widgets stay free of hardcoded styling — they inherit
/// the premium defaults automatically. Consumed by `MaterialApp` in `app.dart`.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      tertiary: AppColors.accent,
      surface: isDark ? AppColors.surfaceDark : AppColors.surface,
      error: AppColors.error,
    );

    final scaffoldBackground =
        isDark ? AppColors.backgroundDark : AppColors.background;
    final textTheme = AppTypography.textTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: textTheme,

      // Cards: large soft corners, no harsh default elevation (we use custom
      // shadows via AppCard where needed).
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        clipBehavior: Clip.antiAlias,
      ),

      // Large, confident primary buttons.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
          textStyle: AppTypography.label.copyWith(fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scaffoldBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.headlineMedium,
      ),

      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(AppTypography.caption),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: AppSpacing.xl,
      ),
    );
  }
}
