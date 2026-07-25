import 'package:flutter/material.dart';

/// A discovery category shown on the "I See Something" categories grid.
/// [token] is the stable id (used for Supabase queries / routing).
class DiscoveryCategory {
  const DiscoveryCategory(
    this.token,
    this.label,
    this.subtitle,
    this.icon,
    this.color,
  );

  final String token;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
}

/// The full category taxonomy (matches the design). Icons are colorful Material
/// glyphs (reliable across platforms); swap for illustrations later.
const discoveryCategories = <DiscoveryCategory>[
  DiscoveryCategory('animals', 'Animals', 'Mammals & more',
      Icons.pets_rounded, Color(0xFFCF7A3A)),
  DiscoveryCategory('birds', 'Birds', 'All kinds of birds',
      Icons.flutter_dash_rounded, Color(0xFF4C9BE0)),
  DiscoveryCategory('reptiles', 'Reptiles', 'Snakes & more',
      Icons.gesture_rounded, Color(0xFF5CA85C)),
  DiscoveryCategory('amphibians', 'Amphibians', 'Frogs & more',
      Icons.water_rounded, Color(0xFF3E9B78)),
  DiscoveryCategory('fish', 'Fish', 'Fresh & saltwater',
      Icons.set_meal_rounded, Color(0xFF3F8FD0)),
  DiscoveryCategory('insects', 'Insects', 'Bugs & more',
      Icons.bug_report_rounded, Color(0xFFE0863C)),
  DiscoveryCategory('trees', 'Trees', 'Explore trees',
      Icons.park_rounded, Color(0xFF4E9A51)),
  DiscoveryCategory('plants', 'Plants', 'Wild & native plants',
      Icons.local_florist_rounded, Color(0xFF5CB85C)),
  DiscoveryCategory('wildflowers', 'Wildflowers', 'Beautiful blooms',
      Icons.filter_vintage_rounded, Color(0xFF9B6ACB)),
  DiscoveryCategory('mushrooms', 'Mushrooms', 'Fungi & more',
      Icons.spa_rounded, Color(0xFFB07D56)),
  DiscoveryCategory('animal_tracks', 'Animal Tracks', 'Tracks & signs',
      Icons.grain_rounded, Color(0xFF9A7B4F)),
  DiscoveryCategory('scenic_views', 'Scenic Views', 'Look around you',
      Icons.landscape_rounded, Color(0xFF3AA6A0)),
  DiscoveryCategory('waterfalls', 'Waterfalls', 'Discover falls',
      Icons.waves_rounded, Color(0xFF3F8FD0)),
  DiscoveryCategory('springs', 'Springs', 'Natural springs',
      Icons.water_drop_rounded, Color(0xFF4CB0D9)),
  DiscoveryCategory('historic_sites', 'Historic Sites', 'History & culture',
      Icons.account_balance_rounded, Color(0xFFCB9A4E)),
  DiscoveryCategory('trail_features', 'Trail Features', 'Bridges & landmarks',
      Icons.hiking_rounded, Color(0xFFB07D56)),
  DiscoveryCategory('unknown', "I Don't Know", 'Help me figure it out',
      Icons.help_rounded, Color(0xFF9B6ACB)),
];
