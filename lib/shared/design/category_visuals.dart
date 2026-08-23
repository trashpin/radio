import 'package:flutter/material.dart';

/// The single centralized category -> icon/color mapping used everywhere a
/// category/type label is shown (Discover cards, Explore cards, event/gem
/// detail, search & filter). Add a category here once and every surface
/// picks it up automatically — no per-screen icon logic.
///
/// Deliberately string-keyword based (not tied to any one feature's enum)
/// so it works against whatever vocabulary a given surface already uses --
/// `LocationType.label` ("State Park"), a Discover interest label
/// ("Festivals"), a Nearby Gem category ("Restaurant"), or a free-text event
/// category from an external source (Ticketmaster's "Music"). Matching is
/// ordered most-specific-first so e.g. "Historic Site" resolves to the
/// history icon rather than a generic "site" fallback.
///
/// Uses Flutter's built-in Material "rounded" icon family exclusively (the
/// same style already used throughout the app) rather than emoji or a new
/// asset/illustration system — one consistent line weight across every
/// category. Each category carries its own accent color so the set reads as
/// lively and varied rather than a uniform wash of one tint; the shared
/// glyph style and badge treatment ([CategoryIcon]) is what keeps that
/// variety feeling designed instead of random.
const List<(List<String>, IconData, Color)> _categoryRules = [
  // Most specific first.
  (['hidden gem', 'local gem', 'gem'], Icons.diamond_rounded, Color(0xFF26C6DA)),
  (['restaurant', 'dining', 'cafe', 'coffee', 'bakery', 'dessert', 'ice cream', 'food'],
      Icons.restaurant_rounded, Color(0xFFFF7043)),
  (['farmers market', 'market'], Icons.shopping_basket_rounded, Color(0xFF8BC34A)),
  (['shop', 'boutique', 'retail'], Icons.shopping_bag_rounded, Color(0xFFEC407A)),
  (['firework', 'festival'], Icons.celebration_rounded, Color(0xFFFFA726)),
  (['spring'], Icons.water_drop_rounded, Color(0xFF29B6F6)),
  (['waterfall', 'falls'], Icons.water_rounded, Color(0xFF42A5F5)),
  (['state park', 'national park', 'county park', 'city park', 'park'],
      Icons.park_rounded, Color(0xFF66BB6A)),
  (['forest', 'tree'], Icons.forest_rounded, Color(0xFF388E3C)),
  (['trailhead', 'trail', 'hike', 'hiking'], Icons.hiking_rounded, Color(0xFF8D6E63)),
  (['bird'], Icons.flutter_dash_rounded, Color(0xFF26A69A)),
  (['wildlife', 'deer', 'animal'], Icons.pets_rounded, Color(0xFF6D4C41)),
  (['wildflower', 'plant', 'flower'], Icons.local_florist_rounded, Color(0xFFEF5DA8)),
  (['museum'], Icons.museum_rounded, Color(0xFF5C6BC0)),
  (['historic', 'history', 'monument', 'memorial', 'landmark'],
      Icons.account_balance_rounded, Color(0xFFC0A044)),
  (['theater', 'theatre'], Icons.theater_comedy_rounded, Color(0xFF8E24AA)),
  (['art', 'craft', 'gallery', 'culture'], Icons.palette_rounded, Color(0xFFAB47BC)),
  (['live music', 'concert', 'music', 'band'], Icons.music_note_rounded, Color(0xFF7E57C2)),
  (['horse', 'equestrian', 'rodeo'], Icons.emoji_nature_rounded, Color(0xFF9C6644)),
  (['car show', 'cruise-in', 'car', 'truck', 'auto'],
      Icons.directions_car_rounded, Color(0xFFE53935)),
  (['kid', 'child'], Icons.child_friendly_rounded, Color(0xFFFFB300)),
  (['family'], Icons.family_restroom_rounded, Color(0xFFFF8A65)),
  (['fish'], Icons.phishing_rounded, Color(0xFF00897B)),
  (['boat', 'kayak', 'canoe', 'paddle'], Icons.directions_boat_rounded, Color(0xFF1E88E5)),
  (['photo'], Icons.camera_alt_rounded, Color(0xFF546E7A)),
  (['bar', 'pub'], Icons.local_bar_rounded, Color(0xFFD4A017)),
  (['night'], Icons.nightlight_rounded, Color(0xFF5C6BC0)),
  (['adventure', 'climb', 'zipline'], Icons.landscape_rounded, Color(0xFF00ACC1)),
  (['camp'], Icons.cabin_rounded, Color(0xFF795548)),
  (['swim', 'pool'], Icons.pool_rounded, Color(0xFF00BCD4)),
  (['scenic', 'overlook', 'sunset', 'vista'], Icons.wb_sunny_rounded, Color(0xFFFF7043)),
  (['lodging', 'hotel'], Icons.hotel_rounded, Color(0xFF78909C)),
  (['free'], Icons.money_off_rounded, Color(0xFF43A047)),
  (['cave', 'cavern'], Icons.landscape_rounded, Color(0xFF6D4C41)),
  (['beach'], Icons.beach_access_rounded, Color(0xFFFFB74D)),
  (['lake', 'river', 'boat ramp', 'creek', 'pond', 'water'],
      Icons.water_rounded, Color(0xFF1E88E5)),
  (['event'], Icons.event_rounded, Color(0xFFFF7043)),
  (['outdoor', 'nature', 'recreation'], Icons.terrain_rounded, Color(0xFF43A047)),
  (['attraction', 'point of interest'], Icons.explore_rounded, Color(0xFFFFA726)),
];

const Color _fallbackColor = Color(0xFF78909C);

/// An icon paired with its category's own accent color.
class CategoryVisual {
  const CategoryVisual(this.icon, this.color);
  final IconData icon;
  final Color color;
}

CategoryVisual _resolve(String? category) {
  final c = (category ?? '').trim().toLowerCase();
  if (c.isNotEmpty) {
    for (final (keywords, icon, color) in _categoryRules) {
      for (final k in keywords) {
        if (c.contains(k)) return CategoryVisual(icon, color);
      }
    }
  }
  return const CategoryVisual(Icons.place_rounded, _fallbackColor);
}

/// Resolves the best-matching icon for a free-text category/type/label
/// string. Never returns null -- an unrecognized category still gets a
/// sensible generic marker rather than leaving a blank space.
IconData categoryIconFor(String? category) => _resolve(category).icon;

/// Resolves the category's own accent color — use this whenever a raw
/// `Icon` (rather than the [CategoryIcon] badge) needs to match the same
/// category coloring, e.g. a small inline icon next to a text label.
Color categoryColorFor(String? category) => _resolve(category).color;

/// A vivid, animated category badge: a soft gradient-tinted circle with the
/// resolved icon centered in it, in that category's own accent color. Drop
/// this in wherever a category needs a visual (a card's photo placeholder,
/// next to a category label, a detail screen's header) instead of
/// hand-rolling icon/color/sizing per screen.
///
/// Plays a brief pop-in (scale + fade) the first time it appears, so a grid
/// or list of category badges feels alive rather than static — purely
/// decorative, never affects layout or interaction.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.category, {super.key, this.size = 36, this.color});

  final String? category;
  final double size;

  /// Overrides the category's own accent color when a screen needs to match
  /// a fixed palette instead (rare — most callers should omit this and let
  /// the category's color show).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final visual = _resolve(category);
    final tint = color ?? visual.color;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(
        scale: 0.85 + (0.15 * t.clamp(0.0, 1.0)),
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [tint.withValues(alpha: 0.28), tint.withValues(alpha: 0.12)],
          ),
        ),
        child: Icon(visual.icon, size: size * 0.56, color: tint),
      ),
    );
  }
}
