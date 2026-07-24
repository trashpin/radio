import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Typography scale for ExplorerOS-Mobile.
///
/// We keep all `TextStyle`s in one place so headings, body text, and captions
/// stay consistent app-wide. These styles are wired into `ThemeData.textTheme`
/// in `app_theme.dart`, so most widgets can simply use
/// `Theme.of(context).textTheme.*` instead of referencing this class directly.
class AppTypography {
  const AppTypography._();

  /// Large screen/page titles.
  static const TextStyle headingLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  /// Section titles.
  static const TextStyle headingMedium = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  /// Card titles / prominent labels.
  static const TextStyle titleSmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// Default body copy.
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  /// Secondary / muted copy.
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  /// Assembles a Material [TextTheme] from the styles above so it can be
  /// plugged directly into [ThemeData].
  static TextTheme textTheme(Color primaryTextColor) {
    return TextTheme(
      headlineLarge: headingLarge.copyWith(color: primaryTextColor),
      headlineMedium: headingMedium.copyWith(color: primaryTextColor),
      titleMedium: titleSmall.copyWith(color: primaryTextColor),
      bodyMedium: bodyMedium.copyWith(color: primaryTextColor),
      bodySmall: caption,
    );
  }
}
