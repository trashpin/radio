import 'package:flutter/widgets.dart';

/// Elevation/shadow tokens for ExplorerOS.
///
/// We favor soft, diffuse shadows (not harsh Material drop shadows) to achieve
/// the calm, high-end look. Reusing these lists keeps card elevation uniform.
class AppShadows {
  const AppShadows._();

  /// Subtle lift for resting cards.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x14000000), // ~8% black
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
  ];

  /// Stronger lift for pressed/featured surfaces.
  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x1F000000), // ~12% black
      blurRadius: 28,
      offset: Offset(0, 14),
    ),
  ];
}
