import 'package:flutter/material.dart';

/// The single centralized category -> icon mapping used everywhere a
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
/// asset/illustration system — one consistent line weight and visual
/// treatment across every category, per the design direction of "designed,
/// not a random collection of emoji."
const List<(List<String>, IconData)> _categoryRules = [
  // Most specific first.
  (['hidden gem', 'local gem', 'gem'], Icons.diamond_rounded),
  (['restaurant', 'dining', 'cafe', 'coffee', 'bakery', 'dessert', 'ice cream', 'food'],
      Icons.restaurant_rounded),
  (['farmers market', 'market'], Icons.shopping_basket_rounded),
  (['shop', 'boutique', 'retail'], Icons.shopping_bag_rounded),
  (['firework', 'festival'], Icons.celebration_rounded),
  (['spring'], Icons.water_drop_rounded),
  (['waterfall', 'falls'], Icons.water_rounded),
  (['state park', 'national park', 'county park', 'city park', 'park'], Icons.park_rounded),
  (['forest', 'tree'], Icons.forest_rounded),
  (['trailhead', 'trail', 'hike', 'hiking'], Icons.hiking_rounded),
  (['bird'], Icons.flutter_dash_rounded),
  (['wildlife', 'deer', 'animal'], Icons.pets_rounded),
  (['wildflower', 'plant', 'flower'], Icons.local_florist_rounded),
  (['museum'], Icons.museum_rounded),
  (['historic', 'history', 'monument', 'memorial', 'landmark'], Icons.account_balance_rounded),
  (['theater', 'theatre'], Icons.theater_comedy_rounded),
  (['art', 'craft', 'gallery', 'culture'], Icons.palette_rounded),
  (['live music', 'concert', 'music', 'band'], Icons.music_note_rounded),
  (['horse', 'equestrian', 'rodeo'], Icons.emoji_nature_rounded),
  (['car show', 'cruise-in', 'car', 'truck', 'auto'], Icons.directions_car_rounded),
  (['kid', 'child'], Icons.child_friendly_rounded),
  (['family'], Icons.family_restroom_rounded),
  (['fish'], Icons.phishing_rounded),
  (['boat', 'kayak', 'canoe', 'paddle'], Icons.directions_boat_rounded),
  (['photo'], Icons.camera_alt_rounded),
  (['bar', 'pub'], Icons.local_bar_rounded),
  (['night'], Icons.nightlight_rounded),
  (['adventure', 'climb', 'zipline'], Icons.landscape_rounded),
  (['camp'], Icons.cabin_rounded),
  (['swim', 'pool'], Icons.pool_rounded),
  (['scenic', 'overlook', 'sunset', 'vista'], Icons.wb_sunny_rounded),
  (['lodging', 'hotel'], Icons.hotel_rounded),
  (['free'], Icons.money_off_rounded),
  (['cave', 'cavern'], Icons.landscape_rounded),
  (['beach'], Icons.beach_access_rounded),
  (['lake', 'river', 'boat ramp', 'creek', 'pond', 'water'], Icons.water_rounded),
  (['event'], Icons.event_rounded),
  (['outdoor', 'nature', 'recreation'], Icons.terrain_rounded),
  (['attraction', 'point of interest'], Icons.explore_rounded),
];

/// Resolves the best-matching icon for a free-text category/type/label
/// string. Never returns null -- an unrecognized category still gets a
/// sensible generic marker rather than leaving a blank space.
IconData categoryIconFor(String? category) {
  final c = (category ?? '').trim().toLowerCase();
  if (c.isEmpty) return Icons.place_rounded;
  for (final (keywords, icon) in _categoryRules) {
    for (final k in keywords) {
      if (c.contains(k)) return icon;
    }
  }
  return Icons.place_rounded;
}

/// A consistent, theme-adaptive category badge: a tinted circle with the
/// resolved icon centered in it. Drop this in wherever a category needs a
/// visual (a card's photo placeholder, next to a category label, a detail
/// screen's header) instead of hand-rolling icon/color/sizing per screen.
///
/// Theme-adaptive by default (`Theme.of(context).colorScheme.primary`) so it
/// looks native wherever it's placed; pass [color] to match a specific
/// screen's own palette (e.g. Explore's or Discover's brand accent) instead.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.category, {super.key, this.size = 36, this.color});

  final String? category;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Icon(categoryIconFor(category), size: size * 0.56, color: tint),
    );
  }
}
