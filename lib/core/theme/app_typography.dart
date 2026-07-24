import 'package:flutter/material.dart';
import 'package:explorer_os_mobile/core/theme/app_colors.dart';

/// Typography scale for ExplorerOS.
///
/// A clear type hierarchy (large, confident headings + calm body text) is
/// central to the premium look. These styles are wired into
/// `ThemeData.textTheme` in `app_theme.dart`, so widgets should normally read
/// `Theme.of(context).textTheme.*` rather than referencing this class directly.
class AppTypography {
  const AppTypography._();

  // Oversized "hero" display used on the dashboard welcome area.
  static const TextStyle display = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.1,
  );

  static const TextStyle headingLarge = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.2,
  );

  static const TextStyle headingMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const TextStyle title = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Builds a Material [TextTheme] for a given [Brightness], applying the right
  /// primary/secondary text colors from [AppColors].
  static TextTheme textTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return TextTheme(
      displayLarge: display.copyWith(color: primary),
      headlineLarge: headingLarge.copyWith(color: primary),
      headlineMedium: headingMedium.copyWith(color: primary),
      titleMedium: title.copyWith(color: primary),
      bodyMedium: body.copyWith(color: primary),
      bodySmall: caption.copyWith(color: secondary),
      labelLarge: label.copyWith(color: primary),
    );
  }
}
