import 'package:flutter/material.dart';

/// ExplorerOS Radio design system — the single source of truth for the premium
/// automotive-radio look. Every color, space, radius, duration and text style
/// used by the Radio experience comes from here (no hardcoded values in
/// widgets), so the whole surface restyles from one place.
///
/// Brand: "ExplorerOS Radio — Every Place Has A Story". Near-black canvas, a
/// vivid leaf-green accent, white type, dark translucent glass panels, generous
/// rounded corners and a soft green glow.
class RD {
  RD._();

  // ── Color ──────────────────────────────────────────────────────────────
  static const Color bg = Color(0xFF05070A); // near-black canvas
  static const Color bgElevated = Color(0xFF0B0F12);
  static const Color panel = Color(0xFF12181C);
  static const Color panelAlt = Color(0xFF1A2226);
  static const Color stroke = Color(0xFF232B30); // hairline borders
  static const Color strokeStrong = Color(0xFF313A40);

  /// Explorer leaf-green accent + a brighter glow variant.
  static const Color green = Color(0xFF8FD24A);
  static const Color greenBright = Color(0xFFA8E85C);
  static const Color greenDim = Color(0xFF5E8F32);

  static const Color live = Color(0xFFE8442E); // LIVE red dot
  static const Color amber = Color(0xFFF2B33D);

  static const Color textPrimary = Color(0xFFF3F7F3);
  static const Color textSecondary = Color(0xFF9BA6A0);
  static const Color textFaint = Color(0xFF69736E);
  static const Color onGreen = Color(0xFF05130A);

  /// Glass panel fill (semi-transparent so hero art shows through overlays).
  static Color glassFill([double opacity = 0.55]) =>
      Colors.black.withValues(alpha: opacity);

  // ── Spacing (8pt-ish scale) ──────────────────────────────────────────────
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;

  // ── Corner radius ─────────────────────────────────────────────────────────
  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 20;
  static const double rXl = 26;
  static const double rPill = 999;

  static BorderRadius brMd = BorderRadius.circular(rMd);
  static BorderRadius brLg = BorderRadius.circular(rLg);
  static BorderRadius brXl = BorderRadius.circular(rXl);

  // ── Elevation / glow ──────────────────────────────────────────────────────
  static List<BoxShadow> get cardShadow => const [
        BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8)),
      ];

  static List<BoxShadow> greenGlow([double strength = 0.45]) => [
        BoxShadow(
          color: green.withValues(alpha: strength),
          blurRadius: 28,
          spreadRadius: 1,
        ),
      ];

  // ── Motion ──────────────────────────────────────────────────────────────
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration med = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 600);
  static const Duration eq = Duration(milliseconds: 900); // equalizer cycle

  // ── Typography ────────────────────────────────────────────────────────────
  static const String _family = 'Roboto'; // system default; heavy weights used

  static const TextStyle wordmark = TextStyle(
    fontFamily: _family,
    fontSize: 26,
    fontWeight: FontWeight.w900,
    letterSpacing: 3,
    height: 1.0,
    color: textPrimary,
  );
  static const TextStyle tagline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 3,
    color: green,
  );
  static const TextStyle sectionLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.5,
    color: green,
  );
  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: textPrimary,
  );
  static const TextStyle cardTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontSize: 13,
    height: 1.3,
    color: textSecondary,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: textSecondary,
  );
  static const TextStyle badge = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
    color: textPrimary,
  );

  /// The Radio experience is always dark; this ThemeData keeps Material 3
  /// widgets (dialogs, sheets, ripples) on-brand.
  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: green,
      brightness: Brightness.dark,
    ).copyWith(
      surface: bg,
      primary: green,
      onPrimary: onGreen,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: _family,
      splashColor: green.withValues(alpha: 0.12),
      highlightColor: green.withValues(alpha: 0.06),
    );
  }
}
