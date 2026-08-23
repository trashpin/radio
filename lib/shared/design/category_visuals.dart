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
const List<(String, List<String>, IconData, Color)> _categoryRules = [
  // Most specific first. The leading string is a stable canonical key (used
  // to look up an admin-assigned fallback photograph — see
  // `category_fallback_images` / [categoryVisualKeyFor]) — it never changes
  // even if the keyword list or wording of a rule changes later.
  ('gems', ['hidden gem', 'local gem', 'gem'], Icons.diamond_rounded, Color(0xFF26C6DA)),
  ('food', ['restaurant', 'dining', 'cafe', 'coffee', 'bakery', 'dessert', 'ice cream', 'food'],
      Icons.restaurant_rounded, Color(0xFFFF7043)),
  ('markets', ['farmers market', 'market'], Icons.shopping_basket_rounded, Color(0xFF8BC34A)),
  ('shopping', ['shop', 'boutique', 'retail'], Icons.shopping_bag_rounded, Color(0xFFEC407A)),
  ('festivals', ['firework', 'festival'], Icons.celebration_rounded, Color(0xFFFFA726)),
  ('springs', ['spring'], Icons.water_drop_rounded, Color(0xFF29B6F6)),
  ('waterfalls', ['waterfall', 'falls'], Icons.water_rounded, Color(0xFF42A5F5)),
  ('parks', ['state park', 'national park', 'county park', 'city park', 'park'],
      Icons.park_rounded, Color(0xFF66BB6A)),
  ('forests', ['forest', 'tree'], Icons.forest_rounded, Color(0xFF388E3C)),
  ('trails', ['trailhead', 'trail', 'hike', 'hiking'], Icons.hiking_rounded, Color(0xFF8D6E63)),
  ('birds', ['bird'], Icons.flutter_dash_rounded, Color(0xFF26A69A)),
  ('wildlife', ['wildlife', 'deer', 'animal'], Icons.pets_rounded, Color(0xFF6D4C41)),
  ('plants', ['wildflower', 'plant', 'flower'], Icons.local_florist_rounded, Color(0xFFEF5DA8)),
  ('museums', ['museum'], Icons.museum_rounded, Color(0xFF5C6BC0)),
  ('history', ['historic', 'history', 'monument', 'memorial', 'landmark'],
      Icons.account_balance_rounded, Color(0xFFC0A044)),
  ('theater', ['theater', 'theatre'], Icons.theater_comedy_rounded, Color(0xFF8E24AA)),
  ('arts_culture', ['art', 'craft', 'gallery', 'culture'], Icons.palette_rounded, Color(0xFFAB47BC)),
  ('live_music', ['live music', 'concert', 'music', 'band'], Icons.music_note_rounded, Color(0xFF7E57C2)),
  ('equestrian', ['horse', 'equestrian', 'rodeo'], Icons.emoji_nature_rounded, Color(0xFF9C6644)),
  ('cars_trucks', ['car show', 'cruise-in', 'car', 'truck', 'auto'],
      Icons.directions_car_rounded, Color(0xFFE53935)),
  ('kids', ['kid', 'child'], Icons.child_friendly_rounded, Color(0xFFFFB300)),
  ('family', ['family'], Icons.family_restroom_rounded, Color(0xFFFF8A65)),
  ('fishing', ['fish'], Icons.phishing_rounded, Color(0xFF00897B)),
  ('boating', ['boat', 'kayak', 'canoe', 'paddle'], Icons.directions_boat_rounded, Color(0xFF1E88E5)),
  ('photography', ['photo'], Icons.camera_alt_rounded, Color(0xFF546E7A)),
  ('bars', ['bar', 'pub'], Icons.local_bar_rounded, Color(0xFFD4A017)),
  ('nightlife', ['night'], Icons.nightlight_rounded, Color(0xFF5C6BC0)),
  ('adventure', ['adventure', 'climb', 'zipline'], Icons.landscape_rounded, Color(0xFF00ACC1)),
  ('camping', ['camp'], Icons.cabin_rounded, Color(0xFF795548)),
  ('swimming', ['swim', 'pool'], Icons.pool_rounded, Color(0xFF00BCD4)),
  ('scenic', ['scenic', 'overlook', 'sunset', 'vista'], Icons.wb_sunny_rounded, Color(0xFFFF7043)),
  ('lodging', ['lodging', 'hotel'], Icons.hotel_rounded, Color(0xFF78909C)),
  ('free', ['free'], Icons.money_off_rounded, Color(0xFF43A047)),
  ('caves', ['cave', 'cavern'], Icons.landscape_rounded, Color(0xFF6D4C41)),
  ('beaches', ['beach'], Icons.beach_access_rounded, Color(0xFFFFB74D)),
  ('water', ['lake', 'river', 'boat ramp', 'creek', 'pond', 'water'],
      Icons.water_rounded, Color(0xFF1E88E5)),
  ('events', ['event'], Icons.event_rounded, Color(0xFFFF7043)),
  ('outdoors', ['outdoor', 'nature', 'recreation'], Icons.terrain_rounded, Color(0xFF43A047)),
  ('attractions', ['attraction', 'point of interest'], Icons.explore_rounded, Color(0xFFFFA726)),
];

/// Every canonical category-visual key, in the same order as
/// [_categoryRules] — the fixed list an admin "assign a category photo" tool
/// iterates over.
List<String> get categoryVisualKeys => [for (final (key, _, _, _) in _categoryRules) key];

const Color _fallbackColor = Color(0xFF78909C);
const String _fallbackKey = 'general';

/// An icon paired with its category's own accent color and canonical key.
class CategoryVisual {
  const CategoryVisual(this.key, this.icon, this.color);
  final String key;
  final IconData icon;
  final Color color;
}

CategoryVisual _resolve(String? category) {
  final c = (category ?? '').trim().toLowerCase();
  if (c.isNotEmpty) {
    for (final (key, keywords, icon, color) in _categoryRules) {
      for (final k in keywords) {
        if (c.contains(k)) return CategoryVisual(key, icon, color);
      }
    }
  }
  return const CategoryVisual(_fallbackKey, Icons.place_rounded, _fallbackColor);
}

/// Resolves a free-text category/type/label to its canonical visual-bucket
/// key (e.g. "Live Music" / "concert" / "Ticketmaster's Music segment" all
/// resolve to `'live_music'`) — the lookup key for an admin-assigned
/// category photograph ([categoryVisualKeys] / `category_fallback_images`).
String categoryVisualKeyFor(String? category) => _resolve(category).key;

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

/// A card's photo area when the item itself has no real photo yet. Falls
/// back through three tiers, in order: (1) an admin-assigned category
/// photograph passed in as [categoryPhotoUrl] (see `category_fallback_images`
/// / [categoryVisualKeyFor] — the caller resolves this, since this widget
/// stays a plain, dependency-free `StatelessWidget`), (2) a genuinely bright,
/// saturated gradient card in the category's own color — not a muted tint
/// over gray — so it still looks designed and alive, and (3) a generic
/// marker if the category itself is unrecognized. Prefer a real per-item
/// photo whenever one is available (see the Media Search Center / event
/// "Find photo" tools) — this is the honest fallback for when one isn't.
class CategoryImagePlaceholder extends StatelessWidget {
  const CategoryImagePlaceholder(
    this.category, {
    super.key,
    this.iconSize = 56,
    this.categoryPhotoUrl,
  });

  final String? category;
  final double iconSize;

  /// An admin-assigned real photograph for this category's visual bucket —
  /// pass `null`/empty when none is assigned to fall straight through to the
  /// icon+gradient tile.
  final String? categoryPhotoUrl;

  @override
  Widget build(BuildContext context) {
    final visual = _resolve(category);
    final c = visual.color;
    final photo = (categoryPhotoUrl ?? '').trim();
    if (photo.isNotEmpty) {
      return Image.network(
        photo,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _gradientTile(visual, c),
      );
    }
    return _gradientTile(visual, c);
  }

  Widget _gradientTile(CategoryVisual visual, Color c) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(c, Colors.white, 0.12)!,
              Color.lerp(c, Colors.black, 0.35)!,
            ],
          ),
        ),
        child: Center(
          child: Icon(visual.icon, size: iconSize, color: Colors.white.withValues(alpha: 0.95)),
        ),
      );
}
