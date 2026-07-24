import 'package:flutter/animation.dart';

/// Animation timing tokens for ExplorerOS.
///
/// Subtle, consistent motion makes the app feel polished. Centralizing
/// durations and curves means every transition/press animation shares the same
/// feel. Keep motion quick and gentle — never flashy.
class AppDurations {
  const AppDurations._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  /// Default easing for most UI transitions.
  static const Curve standardCurve = Curves.easeOutCubic;

  /// Springy curve for press/scale feedback.
  static const Curve emphasizedCurve = Curves.easeOutBack;
}
