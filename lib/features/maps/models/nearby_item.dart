import 'package:flutter/material.dart';

import 'package:explorer_os_mobile/core/data/model.dart';

/// A location-based record surfaced by the real-time "Around Me" discovery
/// system. Mirrors the Supabase `map_locations` schema; no locations are
/// hardcoded — these come from Supabase (or seeded demo data).
class NearbyItem implements Model {
  const NearbyItem({
    required this.id,
    required this.category,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.subcategory,
    this.description,
    this.imageUrl,
    this.audioUrl,
    this.parkCode,
    this.featured = false,
  });

  @override
  final String id;
  final String category;
  final String name;
  final double latitude;
  final double longitude;
  final String? subcategory;
  final String? description;
  final String? imageUrl;
  final String? audioUrl;
  final String? parkCode;
  final bool featured;

  factory NearbyItem.fromJson(Json json) => NearbyItem(
        id: (json['id'] ?? json['location_id'])?.toString() ?? '',
        category: (json['category'] ?? 'other') as String,
        name: (json['name'] ?? '') as String,
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        subcategory: json['subcategory'] as String?,
        description: json['description'] as String?,
        imageUrl: (json['image_url'] ?? json['hero_image']) as String?,
        audioUrl: json['audio_url'] as String?,
        parkCode: json['park_code'] as String?,
        featured: (json['featured'] ?? false) as bool,
      );
}

/// A nearby item paired with its distance (meters) from the user.
typedef NearbyHit = ({NearbyItem item, double meters});

/// Visual style (icon + color + display group) for a category token. Covers all
/// supported discovery + facility categories, with a sensible default.
class NearbyStyle {
  const NearbyStyle(this.group, this.icon, this.color);
  final String group; // display grouping in the Around Me panel
  final IconData icon;
  final Color color;
}

const _defaultStyle = NearbyStyle('Points of Interest',
    Icons.place_rounded, Color(0xFFEE7B2E));

const _nearbyStyles = <String, NearbyStyle>{
  // Wildlife / nature
  'mammals': NearbyStyle('Wildlife', Icons.pets_rounded, Color(0xFFCF7A3A)),
  'wildlife': NearbyStyle('Wildlife', Icons.pets_rounded, Color(0xFFCF7A3A)),
  'birds': NearbyStyle('Birds', Icons.flutter_dash_rounded, Color(0xFF4C9BE0)),
  'reptiles': NearbyStyle('Reptiles', Icons.gesture_rounded, Color(0xFF5CA85C)),
  'amphibians':
      NearbyStyle('Amphibians', Icons.water_rounded, Color(0xFF3E9B78)),
  'fish': NearbyStyle('Fish', Icons.set_meal_rounded, Color(0xFF3F8FD0)),
  'insects': NearbyStyle('Insects', Icons.bug_report_rounded, Color(0xFFE0863C)),
  'plants': NearbyStyle('Plants', Icons.local_florist_rounded, Color(0xFF5CB85C)),
  'trees': NearbyStyle('Trees', Icons.park_rounded, Color(0xFF4E9A51)),
  'wildflowers':
      NearbyStyle('Wildflowers', Icons.filter_vintage_rounded, Color(0xFF9B6ACB)),
  'mushrooms': NearbyStyle('Mushrooms', Icons.spa_rounded, Color(0xFFB07D56)),
  // Water / scenery
  'springs': NearbyStyle('Springs', Icons.water_drop_rounded, Color(0xFF4CB0D9)),
  'waterfalls': NearbyStyle('Waterfalls', Icons.waves_rounded, Color(0xFF3F8FD0)),
  'scenic_overlooks':
      NearbyStyle('Scenic Views', Icons.photo_camera_rounded, Color(0xFF3AA6A0)),
  'scenic_views':
      NearbyStyle('Scenic Views', Icons.landscape_rounded, Color(0xFF3AA6A0)),
  // Culture / trails
  'historic_sites':
      NearbyStyle('Historic Sites', Icons.account_balance_rounded, Color(0xFFCB9A4E)),
  'trails': NearbyStyle('Trails', Icons.hiking_rounded, Color(0xFF9A7B4F)),
  'trail_features':
      NearbyStyle('Trail Features', Icons.signpost_rounded, Color(0xFFB07D56)),
  // Facilities
  'campgrounds':
      NearbyStyle('Campgrounds', Icons.cabin_rounded, Color(0xFF7C8B3A)),
  'visitor_centers':
      NearbyStyle('Visitor Centers', Icons.info_rounded, Color(0xFF4C9BE0)),
  'picnic_areas':
      NearbyStyle('Picnic Areas', Icons.deck_rounded, Color(0xFF7C8B3A)),
  'boat_ramps': NearbyStyle('Boat Ramps', Icons.directions_boat_rounded, Color(0xFF3F8FD0)),
  'fishing_areas':
      NearbyStyle('Fishing', Icons.phishing_rounded, Color(0xFF3F8FD0)),
  'restrooms': NearbyStyle('Restrooms', Icons.wc_rounded, Color(0xFF8E9A93)),
  'parking': NearbyStyle('Parking', Icons.local_parking_rounded, Color(0xFF8E9A93)),
  'ranger_stations':
      NearbyStyle('Ranger Stations', Icons.local_police_rounded, Color(0xFFCB9A4E)),
};

NearbyStyle nearbyStyle(String category) =>
    _nearbyStyles[category] ?? _defaultStyle;
