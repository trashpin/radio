import 'package:flutter/material.dart';

/// One tile on the Discover This Area category grid. [token] is stable and
/// used for routing/content lookups in later phases.
class AreaDiscoveryCategory {
  const AreaDiscoveryCategory(this.token, this.label, this.icon, this.tint);
  final String token;
  final String label;
  final IconData icon;
  final Color tint;
}

/// The category set from the "Discover This Area" spec. Fixed for now —
/// making this admin-configurable (the spec's "Future Categories... should be
/// configurable through the Admin Panel") is a separate follow-up once the
/// individual category experiences below exist to configure.
const areaDiscoveryCategories = <AreaDiscoveryCategory>[
  AreaDiscoveryCategory(
      'history', 'History', Icons.history_edu_rounded, Color(0xFFCB9A4E)),
  AreaDiscoveryCategory(
      'wildlife', 'Wildlife', Icons.pets_rounded, Color(0xFFCF7A3A)),
  AreaDiscoveryCategory(
      'birds', 'Birds', Icons.flutter_dash_rounded, Color(0xFF4C9BE0)),
  AreaDiscoveryCategory('plants_trees', 'Plants & Trees',
      Icons.local_florist_rounded, Color(0xFF5CB85C)),
  AreaDiscoveryCategory(
      'nature', 'Nature', Icons.landscape_rounded, Color(0xFF3AA6A0)),
  AreaDiscoveryCategory(
      'geology', 'Geology', Icons.terrain_rounded, Color(0xFF9A7B4F)),
  AreaDiscoveryCategory('attractions', 'Attractions',
      Icons.attractions_rounded, Color(0xFFB07D56)),
  AreaDiscoveryCategory('driving_tour', 'Driving Tour',
      Icons.directions_car_rounded, Color(0xFF4C9BE0)),
  AreaDiscoveryCategory('walking_tour', 'Walking Tour',
      Icons.directions_walk_rounded, Color(0xFF5CA85C)),
  AreaDiscoveryCategory('audio_experience', 'Audio Experience',
      Icons.headphones_rounded, Color(0xFF9B6ACB)),
];
