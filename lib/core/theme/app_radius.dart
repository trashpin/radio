import 'package:flutter/widgets.dart';

/// Corner-radius tokens for ExplorerOS.
///
/// Large, soft corners are a key part of the premium/automotive-dashboard feel.
/// Cards, buttons, and sheets all reference these values so rounding stays
/// consistent everywhere.
class AppRadius {
  const AppRadius._();

  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}
