import 'package:flutter/widgets.dart';

/// Spacing scale for ExplorerOS.
///
/// A single, consistent spacing rhythm is what makes a UI feel calm and
/// "premium" (lots of breathing room, nothing crowded). Every padding, margin,
/// and gap in the app should use one of these tokens instead of a magic number.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Standard screen edge padding (generous, per the premium design goals).
  static const EdgeInsets screenPadding = EdgeInsets.all(xl);
  static const EdgeInsets screenPaddingH = EdgeInsets.symmetric(horizontal: xl);
}

/// Convenience fixed-size gaps so layouts read cleanly:
/// `const Gap.v(AppSpacing.lg)` instead of `SizedBox(height: 16)`.
class Gap extends StatelessWidget {
  const Gap.v(this._size, {super.key}) : _vertical = true;
  const Gap.h(this._size, {super.key}) : _vertical = false;

  final double _size;
  final bool _vertical;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _vertical ? null : _size,
      height: _vertical ? _size : null,
    );
  }
}
